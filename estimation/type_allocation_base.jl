"""
Accelerated SBM Sampler
James Yuming Yu, 30 June 2023
with optimizations by Jonah Heyl, Kieran Weaver and others
"""

module SBM

using JSON, Random, Distributions, PrettyTables, HTTP

export doit, get_placements, bucket_extract, get_results, estimate_parameters, nice_table, api_to_adjacency, parse_placements

function bucket_estimate(assign, A, T, count, numtier, numtotal)
    """
        Estimate the simplified log-likelihood of the data `A` given type assignment guess `assign`
    """
    @inbounds T .= 0
    @inbounds count .= 0
    L = 0.0

    for i in 1:size(A)[1]
        @simd for j in 1:size(A)[2]
            @inbounds val = numtotal * (assign[j] - 1) + assign[i]
            @inbounds T[val] += A[i, j]
            @inbounds count[val] += 1
        end
    end

    for i in 1:numtotal
        @simd for j in 1:numtier
            @inbounds base = T[i, j]
            if base != 0.0
                @inbounds L += base * log(base / count[i, j])
            end
        end
    end
    return -L
end

function doit(sample, T, count, num_academic, num_acd, num_gov, num_pri, num_tch, num_institutions, numtier, numtotal, blankcount_tol)
    """
        Compute the maximum likelihood estimate of the type assignment via SBM applied to the data `sample`
    """
    
    # some initial states
    cur_objective = Inf
    @inbounds T .= 0
    @inbounds count .= 0
    blankcount = 0
    current_allocation = Vector{Int32}(undef, num_institutions)
    new_tier_lookup = [deleteat!(Vector(1:numtier), i) for i in 1:numtier]
    cursor = 1
    for _ in 1:num_academic
        current_allocation[cursor] = 1
        cursor += 1
    end
    for _ in 1:num_acd # other academic
        current_allocation[cursor] = numtier + 1 # the sinks must stay in fixed types
        cursor += 1
    end
    for _ in 1:num_gov # govt institutions
        current_allocation[cursor] = numtier + 2
        cursor += 1
    end
    for _ in 1:num_pri # private sector
        current_allocation[cursor] = numtier + 3
        cursor += 1
    end
    for _ in 1:num_tch # teaching institutions
        current_allocation[cursor] = numtier + 4
        cursor += 1
    end

    if numtier == 1 # if only one tier is required, we are already done
        return cur_objective, current_allocation
    end

    while true # BEGIN MONTE CARLO REALLOCATION: attempt to reallocate academic institutions to a random spot
        k = rand(1:num_academic)
        @inbounds old_tier = current_allocation[k]
        @inbounds current_allocation[k] = rand(new_tier_lookup[old_tier])
        # check if the new assignment is better
        test_objective = bucket_estimate(current_allocation, sample, T, count, numtier, numtotal)
        if test_objective < cur_objective
            # print("$test_objective ")
            # keep the improvement and continue
            blankcount = 0
            cur_objective = test_objective
        else
            # revert the change
            @inbounds current_allocation[k] = old_tier
            # EARLY STOP: if no improvements are possible at all, stop the sampler
            blankcount += 1
            if (blankcount % blankcount_tol == 0)
                found = false
                for i in 1:num_academic, tier in 1:numtier
                    # conduct a single-department edit
                    @inbounds original = current_allocation[i]
                    @inbounds current_allocation[i] = tier
                    test_objective = bucket_estimate(current_allocation, sample, T, count, numtier, numtotal)
                    # revert the edit after computing the objective so the allocation is not tampered with
                    @inbounds current_allocation[i] = original
                    if test_objective < cur_objective
                        found = true
                        # println("continue ")
                        break
                    end
                end
                if !found
                    return cur_objective, current_allocation
                end
            end
        end
    end
end

function keycheck(outcome)
    """
        Department name conversion helper function for sinks
    """

    if outcome["recruiter_type"] == 5
        return string(outcome["to_name"], " (public sector)")
    elseif outcome["recruiter_type"] in [6, 7]
        return string(outcome["to_name"], " (private sector)")
    elseif outcome["recruiter_type"] == 8
        return string(outcome["to_name"], " (international sink)")
    end
    return outcome["to_name"]
end

function get_placements(YEAR_INTERVAL, DEBUG; bootstrap_samples = 0)
    """
        Extract the relevant placement outcomes from `to_from_by_year.json`
    """

    oid_mapping = Dict{}()
    institution_mapping = Dict{}()

    academic = Set{}()
    academic_to = Set{}()
    academic_builder = []
    rough_sink_builder = []

    # if changing the file source to a web source, separate the following line into an isolated routine so that the web source can be saved before running multiple rounds of allocations (to avoid problems where different rounds have different versions of data if the API is updated while estimating)
    to_from_by_year = JSON.parsefile("to_from_by_year.json")
    for year in keys(to_from_by_year)
        if in(parse(Int32, year), YEAR_INTERVAL)
            # ASSUMPTION: every applicant ID has only one placement
            for (_, placement) in to_from_by_year[year]
                push!(academic, placement["from_institution_name"])
                oid_mapping[string(placement["from_oid"])] = string(placement["from_institution_id"])
                oid_mapping[string(placement["to_oid"])] = string(placement["to_institution_id"])
                institution_mapping[string(placement["from_institution_id"])] = placement["from_institution_name"]
                institution_mapping[string(placement["to_institution_id"])] = placement["to_name"]
                if placement["position_name"] == "Assistant Professor"
                    push!(academic_to, placement["to_name"])
                    # TODO: why is asstprof in rectype Set(Any[5, 4, 7, 2, 10, 3, 1])
                    # FUTURE: if filtering by field, add "&& placement["recruiter_type"] in [1, 2, etc]"
                    push!(academic_builder, placement)
                else
                    push!(rough_sink_builder, placement)
                end
            end
        end
    end

    tch_sink = Set{}() # sink of teaching universities that do not graduate PhDs
    for key in academic_to
        if !(key in academic)
            push!(tch_sink, key)
        end
    end

    acd_sink = Set{}()
    gov_sink = Set{}()
    pri_sink = Set{}()
    sink_builder = []

    for outcome in rough_sink_builder
        if outcome["recruiter_type"] == 5
            # government institution
            push!(gov_sink, string(outcome["to_name"], " (public sector)"))
            push!(sink_builder, outcome)
        elseif outcome["recruiter_type"] in [6, 7]
            # private sector: for and not for profit
            push!(pri_sink, string(outcome["to_name"], " (private sector)"))
            push!(sink_builder, outcome)
        elseif outcome["recruiter_type"] == 8
            # international organizations and think tanks
            push!(acd_sink, string(outcome["to_name"], " (international sink)"))
            push!(sink_builder, outcome)
        end
    end

    # sort to ensure consistent ordering
    academic_list = sort(collect(academic))
    acd_sink_list = sort(collect(acd_sink))
    gov_sink_list = sort(collect(gov_sink))
    pri_sink_list = sort(collect(pri_sink))
    tch_sink_list = sort(collect(tch_sink))
    sinks = vcat(acd_sink_list, gov_sink_list, pri_sink_list, tch_sink_list)
    institutions = vcat(academic_list, sinks)

    out = zeros(Int32, length(institutions), length(academic_list))

    # if bootstrap sampling, only select a few placements
    # if not, this list will be empty (bootstrap_samples = 0)
    """ TODO: if in bootstrap a department doesn't contribute to the likelihood (all zeros), does this bias the data? is this an issue? """
    indices_to_include = rand(1:length(academic_builder)+length(sink_builder), bootstrap_samples)
    outcome_counter = 0

    if bootstrap_samples == 0
        for outcome in academic_builder
            outcome_counter += 1
            out[findfirst(isequal(outcome["to_name"]), institutions), findfirst(isequal(outcome["from_institution_name"]), institutions)] += 1
        end
        for outcome in sink_builder
            outcome_counter += 1
            out[findfirst(isequal(keycheck(outcome)), institutions), findfirst(isequal(outcome["from_institution_name"]), institutions)] += 1
        end
    else
        for index in indices_to_include
            if index <= length(academic_builder)
                outcome = academic_builder[index]
                outcome_counter += 1
                out[findfirst(isequal(outcome["to_name"]), institutions), findfirst(isequal(outcome["from_institution_name"]), institutions)] += 1
            else
                outcome = sink_builder[index - length(academic_builder)]
                outcome_counter += 1
                out[findfirst(isequal(keycheck(outcome)), institutions), findfirst(isequal(outcome["from_institution_name"]), institutions)] += 1
            end
        end
    end

    if DEBUG
        println("Total ", length(academic_builder)+length(sink_builder), " Placements (found ", outcome_counter, " by sequence counting, ", sum(out), " by matrix sum)")
        if bootstrap_samples != 0
            println(" bootstrapping ", bootstrap_samples, " samples")
        end
    end

    # experimental testing suggests not all return values need to be unpacked when calling a function
    # so requesting institution_mapping by the caller is optional
    return out, academic_list, acd_sink_list, gov_sink_list, pri_sink_list, tch_sink_list, sinks, institutions, institution_mapping
end

function bucket_extract(assign, A, numtier, numtotal)
    """
        Extract the Poisson means from data `A` given type assignment `assign`
    """

    b = zeros(Int32, size(A))
    T = zeros(Int32, numtotal, numtier)
    count = zeros(Int32, numtotal, numtier)
    for i in 1:size(A)[1], j in 1:size(A)[2]
        @inbounds val = numtotal * (assign[j] - 1) + assign[i]
        @inbounds b[i, j] = val
        @inbounds T[val] += A[i, j]
        @inbounds count[val] += 1
    end
    
    L = 0.0
    @simd for i in eachindex(A)
        @inbounds L += logpdf(Poisson(T[b[i]]/count[b[i]]), A[i])
    end
    return T, count, L
end

function get_results(placement_rates, counts, est_mat, est_count, est_alloc, institutions, NUMBER_OF_TYPES, numtotal)
    """
        Compiles sorted SBM results
    """

    # TODO: make this function return the placement rates on its own
    @inbounds placement_rates .= 0
    @inbounds counts .= 0

    # mapping o[i]: takes an unsorted SBM-marked type i and outputs the corresponding true, sorted type
    o = zeros(Int32, numtotal)
    o[vcat(sortperm(vec(sum(est_mat, dims = 1)), rev=true), NUMBER_OF_TYPES+1:numtotal)] = 1:numtotal

    # shuffle the cells for the tier to tier placements
    for i in 1:numtotal
        @simd for j in 1:NUMBER_OF_TYPES
            placement_rates[o[i], o[j]] = est_mat[i, j]
            counts[o[i], o[j]] = est_count[i, j]
        end
    end

    # shuffle the allocation
    sorted_allocation = Vector{Int32}(undef, length(institutions))
    for i in 1:length(institutions)
        sorted_allocation[i] = o[est_alloc[i]]
    end

    return sorted_allocation, o
end

#=
NUMBER_OF_TYPES: The number of academic types.
BLANKCOUNT_TOL: After the algorithm sees X iterations with no improvements,
it will attempt to check if absolutely no improvements are possible at all.
This parameter is X.
=#

function estimate_parameters(NUMBER_OF_TYPES, BLANKCOUNT_TOL; SEED=0, DEBUG=false)
    """
        Compute parameter estimates via SBM from the `doit` function
    """

    Random.seed!(SEED)         # for reproducibility: ensures random results are the same on script restart
    YEAR_INTERVAL = 2003:2021  # change this to select the years of data to include in the estimation
    NUMBER_OF_SINKS = 4        # this should not change unless you change the sink structure
    numtotal = NUMBER_OF_TYPES + NUMBER_OF_SINKS

    out, academic_list, acd_sink_list, gov_sink_list, pri_sink_list, tch_sink_list, sinks, institutions, institution_mapping = get_placements(YEAR_INTERVAL, DEBUG)
    placement_rates = zeros(Int32, numtotal, NUMBER_OF_TYPES)
    counts = zeros(Int32, numtotal, NUMBER_OF_TYPES)

    est_obj = nothing
    est_alloc = nothing
    if DEBUG
        @time est_obj, est_alloc = doit(out, placement_rates, counts, length(academic_list), length(acd_sink_list), length(gov_sink_list), length(pri_sink_list), length(tch_sink_list), length(institutions), NUMBER_OF_TYPES, numtotal, BLANKCOUNT_TOL)
    else
        est_obj, est_alloc = doit(out, placement_rates, counts, length(academic_list), length(acd_sink_list), length(gov_sink_list), length(pri_sink_list), length(tch_sink_list), length(institutions), NUMBER_OF_TYPES, numtotal, BLANKCOUNT_TOL)
    end

    est_mat, est_count, full_likelihood = bucket_extract(est_alloc, out, NUMBER_OF_TYPES, numtotal)

    sorted_allocation, o = get_results(placement_rates, counts, est_mat, est_count, est_alloc, institutions, NUMBER_OF_TYPES, numtotal)

    if DEBUG
        if NUMBER_OF_TYPES > 1 && all([!(i in est_alloc) for i in 2:NUMBER_OF_TYPES])
            println()
            println("ERROR IN SAMPLER (no movement detected)")
            println()
        else
            for sorted_type in 1:NUMBER_OF_TYPES
                counter = 0
                inst_hold = []
                println("TYPE $sorted_type:")
                for (i, sbm_type) in enumerate(est_alloc)
                    if sorted_type == o[sbm_type]
                        push!(inst_hold, institutions[i])
                        counter += 1
                    end
                end
                for inst in sort(inst_hold)
                    println("  ", inst)
                end
                println("Total Institutions: $counter")
                println()
            end
        end

        try
            mkdir(".estimates")
        catch
        end

        open(".estimates/estimated_raw_placement_counts.json", "w") do f
            write(f, JSON.string(est_mat))
        end

        println("Estimated Placement Counts (unsorted):")
        display(est_mat)
        println()

        for i in 1:NUMBER_OF_TYPES, j in 1:NUMBER_OF_TYPES
            if i > j # not a diagonal and only check once
                if placement_rates[i, j] <= placement_rates[j, i]
                    println("FAULT: hiring ", i, " with graduating ", j, ": downward rate: ", placement_rates[i, j], ", upward rate: ", placement_rates[j, i])
                end
            end
        end
        open(".estimates/estimated_sorted_placement_counts.json", "w") do f
            write(f, JSON.string(placement_rates))
        end
        println()
        println("Estimated Placement Counts (sorted types):")
        display(placement_rates)
        println()
        open(".estimates/estimated_placement_rates.json", "w") do f
            write(f, JSON.string(placement_rates ./ counts))
        end
        println("Estimated Placement Rates (sorted types):")
        display(placement_rates ./ counts)
        println()

        println("Likelihood: $full_likelihood")
        println()
        println("Check Complete")
    end

    return (; 
        placements = placement_rates,
        counters = counts, 
        means = placement_rates ./ counts, 
        likelihood = full_likelihood, 
        allocation = sorted_allocation, 
        institutions,
        num_institutions = length(institutions),
        institution_mapping
    )
end

## print a nice version of the adjacency matrix with tiers and return the latex
## function by Mike Peters from https://github.com/michaelpetersubc/mapinator/blob/355ad808bddcb392388561d25a63796c81ff04c0/estimation/functions.jl
## TODO: port the API functionality from the same file
function nice_table(t_table, num, numsinks, sinks; has_unassigned = false)
    column_sums = sum(t_table, dims=1)
    row_sums = sum(t_table, dims=2)
    row_sums_augmented = vcat(row_sums, sum(row_sums))
    part = vcat(t_table,column_sums)
    adjacency = hcat(part, row_sums_augmented)
    headers = []
    names = []
    
    for i=1:num-1
        push!(headers, "Tier $i")
        push!(names, "Tier $i")
    end
    
    if has_unassigned == false # regular case
        push!(headers, "Tier $num")
        push!(names, "Tier $num")
    else # need to use an "Unassigned" tier
        push!(headers, "Missing")
        push!(names, "Missing")
    end 
    
    #println(headers)

    push!(headers, "Row Totals")
    names = cat(names, sinks, dims=1)
    #headers = ["Tier 1", "Tier 2", "Tier 3", "Tier 4", "Row totals"]
    #names = ["Tier 1","Tier 2","Tier 3","Tier 4","Other Academic","Government","Private Sector","Teaching Universities","Column Totals"]
    pretty_table(adjacency, header = headers, row_names=names)
    return pretty_table(adjacency, header = headers, row_names=names, backend=Val(:latex))
end

function idcheck(outcome)
    """
        Institution ID conversion helper function for sinks
    """

    if outcome["recruiter_type"] == 5
        return outcome["to_institution_id"] + 5000000
    elseif outcome["recruiter_type"] in [6, 7]
        return outcome["to_institution_id"] + 6000000
    elseif outcome["recruiter_type"] == 8
        return outcome["to_institution_id"] + 8000000
    end
    return outcome["to_institution_id"]
end

function fetch_api(endpoint)
    """
        Extract the relevant placement outcomes from the mapinator API
    """

    api_data = HTTP.get("https://support.econjobmarket.org/api/$(endpoint)")
    return JSON.parse(String(api_data.body))
end

function api_to_adjacency(to_from, tier_data, YEAR_INTERVAL)
    """
        Use the to_from outcomes and tier_data allocation to construct the Poisson means matrix
    """

    # institution IDs
    academic = Dict{}()
    academic_to = Dict{}()

    # placements
    academic_builder = []
    rough_sink_builder = []

    for placement in to_from
        if in(placement["year"], YEAR_INTERVAL)
            academic[parse(Int, placement["from_institution_id"])] = placement["from_institution_name"]
            if placement["position_name"] == "Assistant Professor"
                academic_to[placement["to_institution_id"]] = placement["to_name"]
                push!(academic_builder, placement)
            else
                push!(rough_sink_builder, placement)
            end
        end
    end

    tch_sink = Dict{}() # sink of teaching universities that do not graduate PhDs
    for key in keys(academic_to)
        if !(key in keys(academic))
            tch_sink[key] = string(academic_to[key], " (teaching university)")
        end
    end

    acd_sink = Dict{}()
    gov_sink = Dict{}()
    pri_sink = Dict{}()
    sink_builder = []

    for outcome in rough_sink_builder
        if outcome["recruiter_type"] == 5
            # government institution
            gov_sink[outcome["to_institution_id"]+5000000] = string(outcome["to_name"], " (public sector)")
            push!(sink_builder, outcome)
        elseif outcome["recruiter_type"] in [6, 7]
            # private sector: for and not for profit
            pri_sink[outcome["to_institution_id"]+6000000] = string(outcome["to_name"], " (private sector)")
            push!(sink_builder, outcome)
        elseif outcome["recruiter_type"] == 8
            # international organizations and think tanks
            acd_sink[outcome["to_institution_id"]+8000000] = string(outcome["to_name"], " (international sink)")
            push!(sink_builder, outcome)
        end
    end

    # sort to ensure consistent ordering
    academic_list = sort(collect(keys(academic)))
    acd_sink_list = sort(collect(keys(acd_sink)))
    gov_sink_list = sort(collect(keys(gov_sink)))
    pri_sink_list = sort(collect(keys(pri_sink)))
    tch_sink_list = sort(collect(keys(tch_sink)))
    sinks = vcat(acd_sink_list, gov_sink_list, pri_sink_list, tch_sink_list)
    institutions = vcat(academic_list, sinks)

    institution_names = merge(academic, acd_sink, gov_sink, pri_sink, tch_sink)

    out = zeros(Int32, length(institutions), length(academic_list))
    for outcome in academic_builder
        out[findfirst(isequal(outcome["to_institution_id"]), institutions), findfirst(isequal(parse(Int, outcome["from_institution_id"])), institutions)] += 1
    end
    for outcome in sink_builder
        out[findfirst(isequal(idcheck(outcome)), institutions), findfirst(isequal(parse(Int, outcome["from_institution_id"])), institutions)] += 1
    end

    api_allocation = Dict{}()
    for entry in tier_data
        api_allocation[entry["institution_id"]] = entry["type"]
    end

    NUMBER_OF_TYPES = maximum(values(api_allocation)) + 1 # temporarily accomodate departments with no type allocation (fix TODO)
    NUMBER_OF_SINKS = 4
    numtotal = NUMBER_OF_TYPES + NUMBER_OF_SINKS

    est_alloc = Vector{Int32}(undef, length(institutions))
    cursor = 1
    for institution_id in academic_list
        if institution_id in keys(api_allocation)
            est_alloc[cursor] = api_allocation[institution_id]
        else
            est_alloc[cursor] = NUMBER_OF_TYPES
        end
        cursor += 1
    end
    for _ in acd_sink_list # international organizations
        est_alloc[cursor] = NUMBER_OF_TYPES + 1
        cursor += 1
    end
    for _ in gov_sink_list # govt institutions
        est_alloc[cursor] = NUMBER_OF_TYPES + 2
        cursor += 1
    end
    for _ in pri_sink_list # private sector
        est_alloc[cursor] = NUMBER_OF_TYPES + 3
        cursor += 1
    end
    for _ in tch_sink_list # teaching institutions
        est_alloc[cursor] = NUMBER_OF_TYPES + 4
        cursor += 1
    end

    est_mat, est_count, full_likelihood = bucket_extract(est_alloc, out, NUMBER_OF_TYPES, numtotal)

    #=
    for sorted_type in 1:numtotal
        counter = 0
        println("TYPE $sorted_type:")
        inst_hold = []
        for (i, sbm_type) in enumerate(est_alloc)
            if sorted_type == sbm_type
                push!(inst_hold, institution_names[institutions[i]])
                counter += 1
            end
        end
        sort!(inst_hold)
        for iname in inst_hold
            println("  ", iname)
        end
        println("Total Institutions: $counter")
        println()
    end
    =#

    return est_mat ./ est_count # just the means
end

end