using FileIO, Random, Distributions

include("type_allocation_base.jl")

function resample_simulation(simulated_out, bootstrap_samples)
    simulated_placements = []
    outcome_counter = 0
    bootstrap_out = zeros(Int64, size(simulated_out))
    for index in eachindex(simulated_out)
        for placement in 1:simulated_out[index]
            outcome_counter += 1
            push!(simulated_placements, (index, outcome_counter))
        end
    end
    indices_to_include = rand(simulated_placements, bootstrap_samples)   
    for (index, counter) in indices_to_include    
        bootstrap_out[index] += 1
    end

    return bootstrap_out    
end

function main(; SEED=0)
    YEAR_INTERVAL = 2003:2021  # change this to select the years of data to include in the estimation
    NUMBER_OF_TYPES = 4        # change this to select the number of types to classify academic departments into
    NUMBER_OF_SINKS = 4        # this should not change unless you change the sink structure
    numtotal = NUMBER_OF_TYPES + NUMBER_OF_SINKS
    Random.seed!(SEED)
    
    out, academic_list, acd_sink_list, gov_sink_list, pri_sink_list, tch_sink_list, sinks, institutions = SBM.get_placements(YEAR_INTERVAL, false)
    placement_rates = zeros(Int32, numtotal, NUMBER_OF_TYPES)
    counts = zeros(Int32, numtotal, NUMBER_OF_TYPES)
    
    @time est_obj, est_alloc = SBM.doit(out, placement_rates, counts, length(academic_list), length(acd_sink_list), length(gov_sink_list), length(pri_sink_list), length(tch_sink_list), length(institutions), NUMBER_OF_TYPES, numtotal, 500 * (NUMBER_OF_TYPES-2) + 1000)
    est_mat, est_count, full_likelihood = SBM.bucket_extract(est_alloc, out, NUMBER_OF_TYPES, numtotal)
    sorted_allocation, o = SBM.get_results(placement_rates, counts, est_mat, est_count, est_alloc, institutions, NUMBER_OF_TYPES, numtotal)
    
    tier_poisson_specification = placement_rates ./ counts # the Poisson means
    poisson_variables_means = zeros(size(out)) # to map the means to every department-department pair
    for to_inst in 1:size(out)[1]
        for from_inst in 1:size(out)[2]
            # select the mean corresponding to the types of the department-department pair and load it
            poisson_variables_means[to_inst, from_inst] = tier_poisson_specification[sorted_allocation[to_inst], sorted_allocation[from_inst]]
        end
    end

    poisson_variables = Poisson.(poisson_variables_means)
    Random.seed!(SEED) # re-seed again for consistency
    simulated_out = rand.(poisson_variables)
    println("Total $(sum(simulated_out)) simulation placements sampled")
    
    BOOTSTRAP_SAMPLE_SIZE = sum(out) # change this to make the number of bootstrap samples larger or smaller than the true samples
    SIMULATED_BOOTSTRAP_SAMPLE_SIZE = sum(simulated_out)
    BOOTSTRAP_ROUNDS = 40      # change this to select the number of times to re-generate the placement rates

    est_mat_store = zeros(numtotal, NUMBER_OF_TYPES, BOOTSTRAP_ROUNDS)
    est_count_store = zeros(numtotal, NUMBER_OF_TYPES, BOOTSTRAP_ROUNDS)
    est_alloc_store = zeros(length(institutions), BOOTSTRAP_ROUNDS)
    institutions_store = Array{String}(undef, length(institutions), BOOTSTRAP_ROUNDS)
    likelihood_store = zeros(BOOTSTRAP_ROUNDS)

    simulated_est_mat_store = zeros(numtotal, NUMBER_OF_TYPES, BOOTSTRAP_ROUNDS)
    simulated_est_count_store = zeros(numtotal, NUMBER_OF_TYPES, BOOTSTRAP_ROUNDS)
    simulated_est_alloc_store = zeros(length(institutions), BOOTSTRAP_ROUNDS)
    simulated_institutions_store = Array{String}(undef, length(institutions), BOOTSTRAP_ROUNDS)
    simulated_likelihood_store = zeros(BOOTSTRAP_ROUNDS)

    unsimulated_est_mat_store = zeros(numtotal, NUMBER_OF_TYPES, BOOTSTRAP_ROUNDS)
    unsimulated_est_count_store = zeros(numtotal, NUMBER_OF_TYPES, BOOTSTRAP_ROUNDS)
    unsimulated_est_alloc_store = zeros(length(institutions), BOOTSTRAP_ROUNDS)
    unsimulated_institutions_store = Array{String}(undef, length(institutions), BOOTSTRAP_ROUNDS)
    unsimulated_likelihood_store = zeros(BOOTSTRAP_ROUNDS)

    Random.seed!(SEED) # do not re-seed inside the for loop or else the bootstrap calls will not be different between rounds
    # TODO: isolate bootstrap resampler and the placements generator to enhance neatness
    Threads.@threads for i in 1:BOOTSTRAP_ROUNDS
        println("Commencing true bootstrap round $i on thread $(Threads.threadid())")
        bootstrap_out, bootstrap_academic_list, bootstrap_acd_sink_list, bootstrap_gov_sink_list, bootstrap_pri_sink_list, bootstrap_tch_sink_list, bootstrap_sinks, bootstrap_institutions = SBM.get_placements(YEAR_INTERVAL, false; bootstrap_samples = BOOTSTRAP_SAMPLE_SIZE)
        bootstrap_placement_rates = zeros(Int32, numtotal, NUMBER_OF_TYPES)
        bootstrap_counts = zeros(Int32, numtotal, NUMBER_OF_TYPES)
        @time bootstrap_est_obj, bootstrap_est_alloc = SBM.doit(bootstrap_out, bootstrap_placement_rates, bootstrap_counts, length(bootstrap_academic_list), length(bootstrap_acd_sink_list), length(bootstrap_gov_sink_list), length(bootstrap_pri_sink_list), length(bootstrap_tch_sink_list), length(bootstrap_institutions), NUMBER_OF_TYPES, numtotal, 500 * (NUMBER_OF_TYPES-2) + 1000)
        bootstrap_est_mat, bootstrap_est_count, bootstrap_full_likelihood = SBM.bucket_extract(bootstrap_est_alloc, bootstrap_out, NUMBER_OF_TYPES, numtotal)
        bootstrap_sorted_allocation, bootstrap_o = SBM.get_results(bootstrap_placement_rates, bootstrap_counts, bootstrap_est_mat, bootstrap_est_count, bootstrap_est_alloc, bootstrap_institutions, NUMBER_OF_TYPES, numtotal)
        est_mat_store[:, :, i] = bootstrap_placement_rates ./ bootstrap_counts
        est_count_store[:, :, i] = bootstrap_placement_rates
        est_alloc_store[:, i] = bootstrap_sorted_allocation
        institutions_store[:, i] = bootstrap_institutions
        likelihood_store[i] = bootstrap_full_likelihood
        println("  Completed round $i on thread $(Threads.threadid())")
    end

    Random.seed!(SEED)
    Threads.@threads for i in 1:BOOTSTRAP_ROUNDS
        println("Commencing simulation bootstrap round $i on thread $(Threads.threadid())")
        bootstrap_simulated_out = resample_simulation(simulated_out, SIMULATED_BOOTSTRAP_SAMPLE_SIZE)
        simulated_placement_rates = zeros(Int32, numtotal, NUMBER_OF_TYPES)
        simulated_counts = zeros(Int32, numtotal, NUMBER_OF_TYPES)
        @time simulated_est_obj, simulated_est_alloc = SBM.doit(bootstrap_simulated_out, simulated_placement_rates, simulated_counts, length(academic_list), length(acd_sink_list), length(gov_sink_list), length(pri_sink_list), length(tch_sink_list), length(institutions), NUMBER_OF_TYPES, numtotal, 500 * (NUMBER_OF_TYPES-2) + 1000)
        simulated_est_mat, simulated_est_count, simulated_full_likelihood = SBM.bucket_extract(simulated_est_alloc, bootstrap_simulated_out, NUMBER_OF_TYPES, numtotal)
        simulated_sorted_allocation, simulated_o = SBM.get_results(simulated_placement_rates, simulated_counts, simulated_est_mat, simulated_est_count, simulated_est_alloc, institutions, NUMBER_OF_TYPES, numtotal)
        simulated_est_mat_store[:, :, i] = simulated_placement_rates ./ simulated_counts
        simulated_est_count_store[:, :, i] = simulated_placement_rates
        simulated_est_alloc_store[:, i] = simulated_sorted_allocation
        simulated_institutions_store[:, i] = institutions
        simulated_likelihood_store[i] = simulated_full_likelihood

        unsimulated_placement_rates, unsimulated_counts, unsimulated_full_likelihood = SBM.bucket_extract(sorted_allocation, bootstrap_simulated_out, NUMBER_OF_TYPES, numtotal)
        unsimulated_est_mat_store[:, :, i] = unsimulated_placement_rates ./ unsimulated_counts
        unsimulated_est_count_store[:, :, i] = unsimulated_placement_rates
        unsimulated_est_alloc_store[:, i] = sorted_allocation
        unsimulated_institutions_store[:, i] = institutions
        unsimulated_likelihood_store[i] = unsimulated_full_likelihood

        println("  Completed round $i on thread $(Threads.threadid())")
    end

    bootstrap_output = Dict("placement_rates" => est_mat_store, "placement_counts" => est_count_store, "type_allocation" => est_alloc_store, "dept_labels" => institutions_store, "likelihoods" => likelihood_store)
    simulated_bootstrap_output = Dict("placement_rates" => simulated_est_mat_store, "placement_counts" => simulated_est_count_store, "type_allocation" => simulated_est_alloc_store, "dept_labels" => simulated_institutions_store, "likelihoods" => simulated_likelihood_store)
    unsimulated_bootstrap_output = Dict("placement_rates" => unsimulated_est_mat_store, "placement_counts" => unsimulated_est_count_store, "type_allocation" => unsimulated_est_alloc_store, "dept_labels" => unsimulated_institutions_store, "likelihoods" => unsimulated_likelihood_store)
    mkpath(".estimates")
    save(".estimates/bootstrap_output_basis.jld2", bootstrap_output)
    save(".estimates/bootstrap_output_simulated.jld2", simulated_bootstrap_output)
    save(".estimates/bootstrap_output_unsimulated.jld2", unsimulated_bootstrap_output)
end

main()
