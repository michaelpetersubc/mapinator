include("type_allocation_base.jl")

using Random, Optim

function β(K, likelihoods, λ, numtotal, n)
    return likelihoods[K] - λ * ((K * numtotal) / 2) * n * log(n)
end

function w(β_vec)
    return β_vec ./ sum(β_vec)
end

function objective_to_minimize(λ_vec, range_K, likelihoods, numsink, n)
    λ = λ_vec[1] # just 1-D
    w_vec = w([β(K, likelihoods, λ, K + numsink, n) for K in range_K])
    return sum(w_vec .* log.(w_vec))
end

function main(; SEED=0)
    YEAR_INTERVAL = 2003:2021  # change this to select the years of data to include in the estimation
    NUMBER_OF_SINKS = 4        # this should not change unless you change the sink structure

    println("Compiling data...")
    out, academic_list, acd_sink_list, gov_sink_list, pri_sink_list, tch_sink_list, sinks, institutions = SBM.get_placements(YEAR_INTERVAL, false)

    likelihoods = Dict{}()
    range_K = 1:10
    Threads.@threads for NUMBER_OF_TYPES in range_K  # try setting --threads 6 to avoid locking
        println("Executing K = $NUMBER_OF_TYPES types on thread $(Threads.threadid())")

        numtotal = NUMBER_OF_TYPES + NUMBER_OF_SINKS
        placement_rates = zeros(Int32, numtotal, NUMBER_OF_TYPES)
        counts = zeros(Int32, numtotal, NUMBER_OF_TYPES)

        Random.seed!(SEED) # re-seed after every round
        @time est_obj, est_alloc = SBM.doit(out, placement_rates, counts, length(academic_list), length(acd_sink_list), length(gov_sink_list), length(pri_sink_list), length(tch_sink_list), length(institutions), NUMBER_OF_TYPES, numtotal, 500 * (NUMBER_OF_TYPES-2) + 1000)
        est_mat, est_count, full_likelihood = SBM.bucket_extract(est_alloc, out, NUMBER_OF_TYPES, numtotal)
        likelihoods[NUMBER_OF_TYPES] = full_likelihood
        println("Completed K = $NUMBER_OF_TYPES with likelihood $full_likelihood")
    end

    res = optimize(λ -> objective_to_minimize(λ, range_K, likelihoods, NUMBER_OF_SINKS, length(institutions)), [0.0])
    println("Optimal hyperparameter:")
    # TODO: figure out whether there is a potential issue of a non-singleton argmax set (the argmax needs to be the highest lambda in the set)
    display(Optim.minimizer(res)[1])
    candidate_types = [β(K, likelihoods, Optim.minimizer(res)[1], K + NUMBER_OF_SINKS, length(institutions)) for K in range_K]
    println()
    println("penalized likelihoods: ", candidate_types)
    println("maximum value: ", maximum(candidate_types))
    println(" optimal number of types which maximizes the penalized likelihood: ", argmax(candidate_types))
end

main()

"""
placements = placement_rates,
counters = counts, 
means = placement_rates ./ counts, 
likelihood = full_likelihood, 
allocation = sorted_allocation, 
institutions,
num_institutions = length(institutions)
"""