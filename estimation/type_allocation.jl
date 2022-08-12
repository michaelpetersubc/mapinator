using JSON
using Random

function bucket_estimate(assign::Array{Int32}, A::Matrix{Int32}, T::Array{Float64}, count::Array{Float64}, cur_objective, num)
    @inbounds T .= 0.0
    @inbounds count .= 0.0
    L = 0.0
    for j in 1:size(A)[2]
        @simd for i in 1:size(A)[1]
            @inbounds val = (num + 1) * (assign[j] - 1) + assign[i]
            @inbounds T[val] += A[i, j]
            @inbounds count[val] += 1
        end
    end
    
    for j in 1:size(T)[2]
        @simd for i in 1:size(T)[1]
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

function doit(sample, academic_institutions, sinks, all_institutions, num)
    # some initial states
    num_academic = length(academic_institutions)
    cur_objective = Inf
    T = zeros(Float64, num + 1, num)
    count = zeros(Float64, num + 1, num)
    blankcount = 0
    current_allocation = Array{Int32}(undef, length(all_institutions))
    cursor = 1
    for _ in academic_institutions
        current_allocation[cursor] = 1
        cursor += 1
    end
    for _ in sinks # other academic
        current_allocation[cursor] = num + 1 # the sinks must stay in fixed types
        cursor += 1
    end

    while true # BEGIN MONTE CARLO REALLOCATION: attempt to reallocate academic institutions to a random spot
        k = rand(1:num_academic)
        @inbounds old_tier = current_allocation[k]
        @inbounds new_tier = rand(delete!(Set(1:num), old_tier))
        @inbounds current_allocation[k] = new_tier
        # check if the new assignment is better
        test_objective = bucket_estimate(current_allocation, sample, T, count, cur_objective, num)
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
            if blankcount % 1500 == 0
                found = false
                for i in 1:num_academic, tier in 1:num
                    # conduct a single-department edit
                    @inbounds original = current_allocation[i]
                    @inbounds current_allocation[i] = tier
                    test_objective = bucket_estimate(current_allocation, sample, T, count, cur_objective, num)
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

function bucket_extract(assign, A::Matrix{Int32}, num)
    T = zeros(Int32, num + 1, num)
    count = zeros(Int32, num + 1, num)
    for i in 1:size(A)[1], j in 1:size(A)[2]
            @inbounds T[(num + 1) * (assign[j] - 1) + assign[i]] += A[i, j]
            @inbounds count[(num + 1) * (assign[j] - 1) + assign[i]] += 1
    end
    return T, count
end

function main()
    Random.seed!(1)            # for reproducibility: ensures random results are the same on script restart
    YEAR_INTERVAL = 2003:2021  # change this to select the years of data to include in the estimation
    NUMBER_OF_TYPES = 4        # change this to select the number of types to classify academic departments into

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
                oid_mapping[placement["from_oid"]] = placement["from_institution_id"]
                oid_mapping[placement["to_oid"]] = placement["to_institution_id"]
                institution_mapping[placement["from_institution_id"]] = placement["from_institution_name"]
                institution_mapping[placement["to_institution_id"]] = placement["to_name"]
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
        # CODE global academic, other_placements, pri_sink, gov_sink, acd_sink
        if outcome["recruiter_type"] in ["6","7"]
            # private sector: for and not for profit
            push!(pri_sink, string(outcome["to_name"], " (private sector)"))
        elseif outcome["recruiter_type"] == "5"
            # government institution
            push!(gov_sink, string(outcome["to_name"], " (public sector)"))
        else
            # everything else including terminal academic positions
            push!(acd_sink, string(outcome["to_name"], " (academic sink)"))
        end
    end

    sinks = vcat(collect(acd_sink), collect(gov_sink), collect(pri_sink), collect(tch_sink))
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
        else
            keycheck = string(outcome["to_name"], " (academic sink)")
        end
        out[findfirst(isequal(keycheck), institutions), findfirst(isequal(outcome["from_institution_name"]), institutions)] += 1
    end

    @time est_obj, est_alloc = doit(out, collect(academic), sinks, institutions, NUMBER_OF_TYPES)
    if !(2 in est_alloc) && !(3 in est_alloc) && !(4 in est_alloc)
        println()
        println("ERROR IN SAMPLER (no movement detected)")
        println()
    else
        for j in 1:NUMBER_OF_TYPES
            println("TYPE $j:")
            for (i, type) in enumerate(est_alloc)
                if type == j
                    println("  ", institutions[i])
                end
            end
            println()
        end
    end


    est_mat, est_count = bucket_extract(est_alloc, out, NUMBER_OF_TYPES)
    M = est_mat
    open("est_mat1.json","w") do f
        write(f,JSON.string(est_mat))
    end 

    # the new placements matrix
    placement_rates = zeros(Int32, (NUMBER_OF_TYPES + 1, NUMBER_OF_TYPES))
    new_counts = zeros(Int32, (NUMBER_OF_TYPES + 1, NUMBER_OF_TYPES))
    #row sums in the estimated matrix
    ovector = sum(M, dims=1)
    # row sums reordered highest to lowest
    svector = sortslices(ovector,dims=2, rev=true) 
    #println(svector)
    #println(length(ovector))
    # a mapping from current row index to the index it should have in the new matrix
    o = Dict{}()
    for i in 1:length(ovector)
        for k in 1:length(svector)
            if ovector[1,i] == svector[1,k]
                o[i] = k
                break
            end
        end
    end 
    #println(o)
    P = zeros(Int32, (NUMBER_OF_TYPES + 1, NUMBER_OF_TYPES))
    #shuffle the cells for the tier to tier placements
    for i in 1:NUMBER_OF_TYPES
        for j in 1:NUMBER_OF_TYPES
            placement_rates[o[i],o[j]] = M[i,j]
            new_counts[o[i],o[j]] = est_count[i,j]
        end
    end
    #shuffle the cells for tier to sink placements (separate since sink row indices don't change)
    for i in NUMBER_OF_TYPES+1:NUMBER_OF_TYPES+1
        for j in 1:NUMBER_OF_TYPES
            placement_rates[i,o[j]] = M[i,j]
            new_counts[i,o[j]] = est_count[i,j]
        end
    end

    for i in 1:NUMBER_OF_TYPES, j in 1:NUMBER_OF_TYPES
        if i > j # not a diagonal and only check once
            if placement_rates[i, j] <= placement_rates[j, i]
                println("FAULT: hiring ", i, " with graduating ", j, ": downward rate: ", placement_rates[i, j], ", upward rate: ", placement_rates[j, i])
            end
        end
    end
    open("est_mat2.json","w") do f
        write(f,JSON.string(placement_rates))
    end 
    open("est_lambda.json","w") do f
        write(f,JSON.string(placement_rates ./ new_counts))
    end 
    println("Check Complete")
end

main()