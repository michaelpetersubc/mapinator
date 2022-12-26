"""
Accelerated SBM Sampler
James Yuming Yu, 26 December 2022
with optimizations by Jonah Heyl and Kieran Weaver
"""

using JSON
using Random
using Distributions

function bucket_estimate(assign::Array{Int32}, A::Matrix{Int32}, T::Array{Float64}, count::Array{Float64}, cur_objective, numtier, numtotal)
    @inbounds T .= 0.0
    @inbounds count .= 0.0
    L = 0.0
    for j in 1:size(A)[2]
        @simd for i in 1:size(A)[1]
            @inbounds val = (numtotal) * (assign[j] - 1) + assign[i]
            @inbounds T[val] += A[i, j]
            @inbounds count[val] += 1
        end
    end

    for j in 1:numtier
        @simd for i in 1:numtotal
            @inbounds base = T[i, j]
            if base != 0.0
                @inbounds L += base * log(base / count[i, j])
            end
        end
    end
    return -L
end

function doit(sample, academic_institutions, acd_sink, gov_sink, pri_sink, tch_sink, all_institutions, numtier, numtotal, blankcount_tol)
    # some initial states
    num_academic = length(academic_institutions)
    cur_objective = Inf
    T = zeros(Float64, numtotal, numtier)
    count = zeros(Float64, numtotal, numtier)
    blankcount = 0
    current_allocation = Array{Int32}(undef, length(all_institutions))
    new_tier_lookup = [deleteat!(Vector(1:numtier), i) for i in 1:numtier]
    cursor = 1
    for _ in academic_institutions
        current_allocation[cursor] = 1
        cursor += 1
    end
    for _ in acd_sink # other academic
        current_allocation[cursor] = numtier + 1 # the sinks must stay in fixed types
        cursor += 1
    end
    for _ in gov_sink # govt institutions
        current_allocation[cursor] = numtier + 2
        cursor += 1
    end
    for _ in pri_sink # private sector
        current_allocation[cursor] = numtier + 3
        cursor += 1
    end
    for _ in tch_sink # teaching institutions
        current_allocation[cursor] = numtier + 4
        cursor += 1
    end

    while true # BEGIN MONTE CARLO REALLOCATION: attempt to reallocate academic institutions to a random spot
        k = rand(1:num_academic)
        @inbounds old_tier = current_allocation[k]
        @inbounds new_tier = rand(new_tier_lookup[old_tier])
        @inbounds current_allocation[k] = new_tier
        # check if the new assignment is better
        test_objective = bucket_estimate(current_allocation, sample, T, count, cur_objective, numtier, numtotal)
        if test_objective < cur_objective
            print("$test_objective ")
            # keep the improvement and continue
            blankcount = 0
            cur_objective = test_objective
        else
            # revert the change
            @inbounds current_allocation[k] = old_tier
            # EARLY STOP: if no improvements are possible at all, stop the sampler 
            blankcount += 1
            if blankcount % blankcount_tol == 0
                found = false
                for i in 1:num_academic, tier in 1:numtier
                    # conduct a single-department edit
                    @inbounds original = current_allocation[i]
                    @inbounds current_allocation[i] = tier
                    test_objective = bucket_estimate(current_allocation, sample, T, count, cur_objective, numtier, numtotal)
                    # revert the edit after computing the objective so the allocation is not tampered with
                    @inbounds current_allocation[i] = original
                    if test_objective < cur_objective
                        found = true
                        println("continue ")
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

function bucket_extract(assign, A::Matrix{Int32}, numtier, numtotal)
    T = zeros(Int32, numtotal, numtier)
    count = zeros(Int32, numtotal, numtier)
    for i in 1:size(A)[1], j in 1:size(A)[2]
        @inbounds T[(numtotal)*(assign[j]-1)+assign[i]] += A[i, j]
        @inbounds count[(numtotal)*(assign[j]-1)+assign[i]] += 1
    end
    return T, count
end

function variance_opg(assign, o, A, est_mat, est_count, numtier, numtotal)
    variance = zeros(numtotal, numtier)
    for i in 1:size(A)[1], j in 1:size(A)[2]
        est_mean = est_mat[o[assign[i]], o[assign[j]]] / est_count[o[assign[i]], o[assign[j]]]
        variance[o[assign[i]], o[assign[j]]] += ((A[i, j] / est_mean) - 1)^2
    end
    for i in 1:numtotal, j in 1:numtier
        variance[i, j] = est_count[i, j] / variance[i, j] # (1 / n * sum)^-1
    end
    return variance
end

function variance_poisson(assign, o, A, est_mat, est_count, numtier, numtotal)
    variance = zeros(numtotal, numtier)
    for i in 1:size(A)[1], j in 1:size(A)[2]
        est_mean = est_mat[o[assign[i]], o[assign[j]]] / est_count[o[assign[i]], o[assign[j]]]
        variance[o[assign[i]], o[assign[j]]] += (A[i, j] - est_mean)^2
    end
    for i in 1:numtotal, j in 1:numtier
        variance[i, j] /= (est_count[i, j])
    end
    return variance
end

function variance_hessian(assign, o, A, est_mat, est_count, numtier, numtotal)
    variance = zeros(numtotal, numtier)
    for i in 1:size(A)[1], j in 1:size(A)[2]
        est_mean = est_mat[o[assign[i]], o[assign[j]]] / est_count[o[assign[i]], o[assign[j]]]
        variance[o[assign[i]], o[assign[j]]] += A[i, j] / (est_mean^2)
    end
    for i in 1:numtotal, j in 1:numtier
        variance[i, j] = est_count[i, j] / variance[i, j] # (1 / n * sum)^-1
    end
    return variance
end

function confint(est_mat, est_count, variance, numtier, numtotal)
    res = Array{Any}(undef, numtotal, numtier)
    z = 1.96
    for i in 1:numtotal, j in 1:numtier
        mean = est_mat[i, j] / est_count[i, j]
        res[i, j] = (mean - (z * sqrt(variance[i, j] / est_count[i, j])), mean + (z * sqrt(variance[i, j] / est_count[i, j])))
    end
    return res
end

function variance_sandwich(opg, hessian)
    return hessian .* hessian ./ opg
end

#=
Parameter 1: The number of academic types.
Parameter 2: After the algorithm sees k iterations with no improvements, 
it will attempt to check if absolutely no improvements are possible at all.
This parameter is k.
=#

function main(NUMBER_OF_TYPES, BLANKCOUNT_TOL; SEED = 0)
    Random.seed!(SEED)            # for reproducibility: ensures random results are the same on script restart
    YEAR_INTERVAL = 2003:2021  # change this to select the years of data to include in the estimation

    NUMBER_OF_SINKS = 4        # this should not change unless you change the sink structure
    numtotal = NUMBER_OF_TYPES + NUMBER_OF_SINKS

    oid_mapping = Dict{}()
    institution_mapping = Dict{}()

    academic = Set{}()
    academic_to = Set{}()
    academic_builder = Set{}()
    sink_builder = Set{}()

    to_from_by_year = JSON.parsefile("to_from_by_year.json")
    for year in keys(to_from_by_year)
        if in(parse(Int32, year), YEAR_INTERVAL)
            for (_, placement) in to_from_by_year[year]
                push!(academic, placement["from_institution_name"])
                push!(academic_to, placement["to_name"])
                oid_mapping[string(placement["from_oid"])] = string(placement["from_institution_id"])
                oid_mapping[string(placement["to_oid"])] = string(placement["to_institution_id"])
                institution_mapping[string(placement["from_institution_id"])] = placement["from_institution_name"]
                institution_mapping[string(placement["to_institution_id"])] = placement["to_name"]
                if placement["position_name"] == "Assistant Professor"
                    push!(academic_builder, placement)
                else
                    push!(sink_builder, placement)
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

    for outcome in sink_builder
        if outcome["recruiter_type"] in [6, 7, "6", "7"]
            # private sector: for and not for profit
            push!(pri_sink, string(outcome["to_name"], " (private sector)"))
        elseif outcome["recruiter_type"] in [5, "5"]
            # government institution
            push!(gov_sink, string(outcome["to_name"], " (public sector)"))
        else
            # everything else including terminal academic positions
            push!(acd_sink, string(outcome["to_name"], " (academic sink)"))
        end
    end

    academic_list = collect(academic)
    acd_sink_list = collect(acd_sink)
    gov_sink_list = collect(gov_sink)
    pri_sink_list = collect(pri_sink)
    tch_sink_list = collect(tch_sink)
    sinks = vcat(acd_sink_list, gov_sink_list, pri_sink_list, tch_sink_list)
    institutions = vcat(academic_list, sinks)

    out = zeros(Int32, length(institutions), length(academic_list))

    i = 0
    for outcome in academic_builder
        i += 1
        out[findfirst(isequal(outcome["to_name"]), institutions), findfirst(isequal(outcome["from_institution_name"]), institutions)] += 1
    end
    for outcome in sink_builder
        i += 1
        keycheck = ""
        if outcome["recruiter_type"] in [6, 7, "6", "7"]
            keycheck = string(outcome["to_name"], " (private sector)")
        elseif outcome["recruiter_type"] in [5, "5"]
            keycheck = string(outcome["to_name"], " (public sector)")
        else
            keycheck = string(outcome["to_name"], " (academic sink)")
        end
        out[findfirst(isequal(keycheck), institutions), findfirst(isequal(outcome["from_institution_name"]), institutions)] += 1
    end

    @time est_obj, est_alloc = doit(out, academic_list, acd_sink_list, gov_sink_list, pri_sink_list, tch_sink_list, institutions, NUMBER_OF_TYPES, numtotal, BLANKCOUNT_TOL)

    est_mat, est_count = bucket_extract(est_alloc, out, NUMBER_OF_TYPES, numtotal)
    M = est_mat

    # the new placements matrix
    placement_rates = zeros(Int32, (numtotal, NUMBER_OF_TYPES))
    new_counts = zeros(Int32, (numtotal, NUMBER_OF_TYPES))
    #row sums in the estimated matrix
    ovector = sum(M, dims=1)
    # row sums reordered highest to lowest
    svector = sortslices(ovector, dims=2, rev=true)
    #println(svector)
    #println(length(ovector))
    # a mapping from current row index to the index it should have in the new matrix
    o = Dict{}()
    for i in 1:length(ovector)
        for k in 1:length(svector)
            if ovector[1, i] == svector[1, k]
                o[i] = k
                break
            end
        end
    end
    for i in 1:NUMBER_OF_SINKS
        o[NUMBER_OF_TYPES+i] = NUMBER_OF_TYPES+i # deal with sinks for variance calculations
    end
    #println(o)
    P = zeros(Int32, (numtotal, NUMBER_OF_TYPES))
    #shuffle the cells for the tier to tier placements
    for i in 1:NUMBER_OF_TYPES
        for j in 1:NUMBER_OF_TYPES
            placement_rates[o[i], o[j]] = M[i, j]
            new_counts[o[i], o[j]] = est_count[i, j]
        end
    end
    #shuffle the cells for tier to sink placements (separate since sink row indices don't change)
    for i in NUMBER_OF_TYPES+1:numtotal
        for j in 1:NUMBER_OF_TYPES
            placement_rates[i, o[j]] = M[i, j]
            new_counts[i, o[j]] = est_count[i, j]
        end
    end

    if !(2 in est_alloc) && !(3 in est_alloc) && !(4 in est_alloc)
        println()
        println("ERROR IN SAMPLER (no movement detected)")
        println()
    else
        for j in 1:NUMBER_OF_TYPES
            counter = 0
            println("TYPE $j:")
            for (i, type) in enumerate(est_alloc)
                if o[type] == j
                    println("  ", institutions[i])
                    counter += 1
                end
            end
            println("Total Institutions: $counter")
        end
    end
    open("estimated_raw_placement_counts.json", "w") do f
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
    open("sorted_estimated_placement_counts.json", "w") do f
        write(f, JSON.string(placement_rates))
    end
    println("Estimated Placement Counts (sorted types):")
    display(placement_rates)
    println()
    open("estimated_placement_rates.json", "w") do f
        write(f, JSON.string(placement_rates ./ new_counts))
    end
    println("Estimated Placement Rates (sorted types):")
    display(placement_rates./ new_counts)
    println()
    println("SAMPLES:")
    display(new_counts)
    println()
    println("MEAN:")
    display(placement_rates ./ new_counts)
    println()

    var_opg = variance_opg(est_alloc, o, out, placement_rates, new_counts, NUMBER_OF_TYPES, numtotal)
    var_hessian = variance_hessian(est_alloc, o, out, placement_rates, new_counts, NUMBER_OF_TYPES, numtotal)
    println("MLE PARAMETER VARIANCE: OPG")
    display(var_opg)
    println()
    println("MLE PARAMETER VARIANCE: HESSIAN")
    display(var_hessian)
    println()
    println("MLE PARAMETER VARIANCE: SANDWICH")
    display(variance_sandwich(var_opg, var_hessian))
    println()
    println("SAMPLE VARIANCES")
    display(variance_poisson(est_alloc, o, out, placement_rates, new_counts, NUMBER_OF_TYPES, numtotal))
    println()
    println("95% CONFIDENCE INTERVAL ON MLE MEAN")
    display(confint(est_mat, est_count, var_hessian, NUMBER_OF_TYPES, numtotal))
    println()
    println("Check Complete")
    return placement_rates, placement_rates ./ new_counts, est_obj, est_alloc, institutions, o, length(institutions)
end