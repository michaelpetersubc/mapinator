module functions

using JSON
using PrettyTables, HTTP

export doit, process_data, tiered_allocation, nice_table, create_adjacency_matrix

## create the adjacency matrix from processed data
function create_adjacency_matrix(academic_builder, sink_builder, academic,acd_sink, gov_sink, pri_sink, tch_sink, postdoc, lecturer)
 sinks = vcat(collect(acd_sink), collect(gov_sink), collect(pri_sink), collect(tch_sink), collect(postdoc), collect(lecturer))
    institutions = vcat(collect(academic), sinks)

    out = zeros(Int32, length(institutions), length(collect(academic)))
    i = 0
    for outcome in academic_builder
        i += 1
        out[findfirst(isequal(outcome["to_name"]), institutions), findfirst(isequal(outcome["from_institution_name"]), institutions)] += 1
    end
    for outcome in sink_builder
            i += 1
            keycheck = ""
            if outcome["recruiter_type"] in ["6", "7"]
                keycheck = string(outcome["to_name"], " (private sector)")
            elseif outcome["recruiter_type"] == "5"
                keycheck = string(outcome["to_name"], " (public sector)")
            elseif outcome["postype"] == "6"
                keycheck = string(outcome["to_name"], " (postdoc)")
            elseif outcome["postype"] in ["5", "7"]
                keycheck = string(outcome["to_name"], " (lecturer)")
            else
                keycheck = string(outcome["to_name"], " (academic sink)")
            end
            out[findfirst(isequal(keycheck), institutions), findfirst(isequal(outcome["from_institution_name"]), institutions)] += 1
    end
    return institutions, out
end

## print a nice version of the adjacency matrix with tiers and return the latex
function nice_table(t_table, num, numsinks, sinks)
    column_sums = sum(t_table, dims=1)
    row_sums = sum(t_table, dims=2)
    row_sums_augmented = vcat(row_sums, sum(row_sums))
    part = vcat(t_table,column_sums)
    adjacency = hcat(part, row_sums_augmented)
    headers = []
    names = []
    for i=1:num
        push!(headers, "Tier $i")
        push!(names, "Tier $i")
    end
    #println(headers)

    push!(headers, "Row Totals")
    names = cat(names, sinks, dims=1)
    #headers = ["Tier 1", "Tier 2", "Tier 3", "Tier 4", "Row totals"]
    #names = ["Tier 1","Tier 2","Tier 3","Tier 4","Other Academic","Government","Private Sector","Teaching Universities","Column Totals"]
    pretty_table(adjacency, header = headers, row_names=names)
    return pretty_table(adjacency, header = headers, row_names=names, backend=Val(:latex))
    
end

## transform the original allocation to a tiered allocation, return the allocation to tiers and the new adjacency matrix
 function tiered_allocation(M, est_count, institutions,est_alloc, NUM, NUMSINKS)
    placement_rates = zeros(Int32, (NUM + NUMSINKS, NUM))
    new_counts = zeros(Int32, (NUM + NUMSINKS, NUM))
    #row sums in the estimated matrix
    ovector = sum(M, dims=1)
    # row sums reordered highest to lowest
    #println(ovector)
    svector = sortslices(ovector, dims=2, rev=true)
    #println(svector)
    #println(length(ovector))
    # a mapping from current row index to the index it should have in the new matrix
    # this should be the type to tier mapping
    o = Dict{}()
    for i in 1:length(ovector)
        for k in 1:length(svector)
            if ovector[1, i] == svector[1, k]
                o[i] = k
                break
            end
        end
    end
    o[NUM+NUMSINKS] = NUM+NUMSINKS # deal with sinks for variance calculations
    #println(o)
    P = zeros(Int32, (NUM + NUMSINKS, NUM))
    #shuffle the cells for the tier to tier placements
    for i in 1:NUM
        for j in 1:NUM
            placement_rates[o[i], o[j]] = M[i, j]
            new_counts[o[i], o[j]] = est_count[i, j]
        end
    end
    #shuffle the cells for tier to sink placements (separate since sink row indices don't change)
    for i in NUM+1:NUM+NUMSINKS
        for j in 1:NUM
            placement_rates[i, o[j]] = M[i, j]
            new_counts[i, o[j]] = est_count[i, j]
        end
    end

    for i in 1:NUM, j in 1:NUM
        if i > j # not a diagonal and only check once
            if placement_rates[i, j] <= placement_rates[j, i]
                println("FAULT: hiring ", i, " with graduating ", j, ": downward rate: ", placement_rates[i, j], ", upward rate: ", placement_rates[j, i])
            end
        end
    end
    tiered_allocation = Array{Int32}(undef, length(institutions))
    for (i, type) in enumerate(est_alloc)
        if haskey(o, type)
            tiered_allocation[i] = o[type]
        else
            tiered_allocation[i] = type
        end
    end
    return placement_rates, tiered_allocation
end


## a function to read data then process it into academic and sinks

function bucket_extract(assign, A::Matrix{Int32}, num,  numsink)
    T = zeros(Int32, num + numsink, num)
    count = zeros(Int32, num + numsink, num)
    for i in 1:size(A)[1], j in 1:size(A)[2]
        @inbounds T[(num+numsink)*(assign[j]-1)+assign[i]] += A[i, j]
        @inbounds count[(num+numsink)*(assign[j]-1)+assign[i]] += 1
    end
    return T, count
end

function get_data(url)
    resp = HTTP.get(url);
    es = String(resp.body)
    return placements = JSON.parse(es)
end

function process_data(YEAR_INTERVAL)
    url = "https://support.econjobmarket.org/api/placement_data"
    placements = get_data(url);
    i = 0
    oid_mapping = Dict{}()
    institution_mapping = Dict{}()
    academic = Set{}()
    academic_to = Set{}()
    academic_builder = Set{}()
    sink_builder = Set{}()
    for placement in placements
        if in(parse(Int64, placement["year"]), YEAR_INTERVAL)
            push!(academic, placement["from_institution_name"])
            if placement["position_name"] == "Assistant Professor"
                    push!(academic_to, placement["to_name"])
            end
            oid_mapping[placement["from_oid"]] = placement["from_institution_id"]
            oid_mapping[placement["to_oid"]] = placement["to_institution_id"]
            institution_mapping[placement["from_institution_id"]] = placement["from_institution_name"]
            institution_mapping[placement["to_institution_id"]] = placement["to_name"]
            if placement["postype"] == "1"
                push!(academic_builder, placement)
            else
                push!(sink_builder, placement)
            end
        end
    end

    println("Debug: ", length(placements), " returned from api")
    println("Debug: ", length(academic_builder), " academic placements")
    println("Debug: ", length(sink_builder), " sinks")
    println("Debug: ", length(academic_builder)+length(sink_builder), " in all")
        
    tch_sink = Set{}() # sink of teaching universities that do not graduate PhDs
    for key in academic_to
        if !(key in academic)
            push!(tch_sink, key)
        end
    end


    acd_sink = Set{}()
    gov_sink = Set{}()
    pri_sink = Set{}()
    postdoc = Set{}()
    lecturer = Set{}()
    for outcome in sink_builder
        # CODE global academic, other_placements, pri_sink, gov_sink, acd_sink
        if outcome["recruiter_type"] in ["6", "7"]
            # private sector: for and not for profit
            push!(pri_sink, string(outcome["to_name"], " (private sector)"))
        elseif outcome["recruiter_type"] == "5"
            # government institution
            push!(gov_sink, string(outcome["to_name"], " (public sector)"))
        elseif outcome["postype"] == "6"
            #postdoc
            push!(postdoc, string(outcome["to_name"], " (postdoc)"))
        elseif outcome["postype"] in ["5", "7"]
            #postdoc
            push!(lecturer, string(outcome["to_name"], " (lecturer)"))
        else
            # everything else including terminal academic positions
            push!(acd_sink, string(outcome["to_name"], " (academic sink)"))
        end
    end
    return academic_builder, sink_builder, academic, acd_sink, gov_sink, pri_sink, tch_sink, postdoc, lecturer, institution_mapping
end
#=
    Two functions used to assign universities to communities
=#
"""
    bucket_estimate(assign, A, T, count, estimates, current_objective, num, numsink)

    `assign` - a current assignment to an array of length equal the number of all institutions - indicies match the indices of the set of institutions
    `A` - the raw adjacency matrix
    `T` and `count` are placeholders from the doit routine, to save memory
    `estimates` - a placeholder for the current estimates of the possion parameters

    returns the current value -L  which is monotonically related to the likeliihood of the adjacency matrix given the categorization in assign
"""
function bucket_estimate(assign::Array{Int32}, A::Matrix{Int32}, T::Array{Float64},count::Array{Float64}, cur_objective, num, numsink)
    @inbounds T .= 0.0
    @inbounds count .= 0.0
    L = 0.0
    for j in 1:size(A)[2]
        @simd for i in 1:size(A)[1]
            @inbounds val = (num + numsink) * (assign[j] - 1) + assign[i]
            @inbounds T[val] += A[i, j]
            @inbounds count[val] += 1
        end
    end

    for j in 1:num
        @simd for i in 1:num+numsink
            @inbounds base = T[i, j]
            if base != 0.0
                @inbounds L += base * log(base / count[i, j])
            end
        end
        if -L > cur_objective
            return Inf
        end
    end
    return -L
end

"""
    doit(sample, academic_institutions, asink, gsink, psink, tsink, all_intitutions, num, numsink)

    This is the main iterative routine used to test assignments of universities to communities
    `sample` - the raw adjacency matrix - Int32 matrix with NUM+NUMSINK rows and NUM columns
    `academic_institutions` - a set of strings with institution names
"""
function doit(sample, academic_institutions, asink, gsink, psink, tsink, postdoc, lecturer, all_institutions, num, numsink)
    # some initial states
    num_academic = length(academic_institutions)
    cur_objective = Inf
    T = zeros(Float64, num + numsink, num)
    estimates = zeros(Float64, num + numsink, num)
    cur_estimates = zeros(Float64, num + numsink, num)
    count = zeros(Float64, num + numsink, num)
    blankcount = 0
    # put every academic department in group 1 and assign every sink to its appropriate tier to start
    current_allocation = Array{Int32}(undef, length(all_institutions))
    cursor = 1
    for _ in academic_institutions
        current_allocation[cursor] = 1
        cursor += 1
    end
    for key in asink # other academic
        current_allocation[cursor] = num + min(1, numsink)
        cursor += 1
    end
    for key in gsink # public sector
        current_allocation[cursor] = num + min(2, numsink)
        cursor += 1
    end
    for key in psink # private sector
        current_allocation[cursor] = num + min(3, numsink)
        cursor += 1
    end
    for key in tsink # assistant professor at teaching universities
        current_allocation[cursor] = num + min(4, numsink)
        cursor += 1
    end
    for key in postdoc # assistant professor at teaching universities
        current_allocation[cursor] = num + min(5, numsink)
        cursor += 1
    end
    for key in lecturer # assistant professor at teaching universities
        current_allocation[cursor] = num + min(6, numsink)
        cursor += 1
    end
    while true # BEGIN MONTE CARLO REALLOCATION: attempt to reallocate academic institutions to a random spot
        k = rand(1:num_academic)
        # reallocates one department at a time
        @inbounds old_tier = current_allocation[k]
        @inbounds new_tier = rand(delete!(Set(1:num), old_tier))
        @inbounds current_allocation[k] = new_tier
        # check if the new assignment is better
        test_objective = bucket_estimate(current_allocation, sample, T, count, cur_objective, num, numsink)
        if test_objective < cur_objective
            #print("$test_objective ")
            # keep the improvement and continue
            blankcount = 0
            cur_objective = test_objective
        else
            # revert the change
            @inbounds current_allocation[k] = old_tier
            # EARLY STOP: if no improvements are possible at all, stop the sampler 
            blankcount += 1
            if blankcount % 1500 == 0
                found = false
                for i in 1:num_academic, tier in 1:num
                    # conduct a single-department edit
                    @inbounds original = current_allocation[i]
                    @inbounds current_allocation[i] = tier
                    test_objective = bucket_estimate(current_allocation, sample, T, count, cur_objective, num, numsink)
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

end