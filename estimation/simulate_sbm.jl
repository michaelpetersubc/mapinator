using Random, Distributions

include("type_allocation_base.jl")

function old_parameters_random_data(; SEED=0)
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
    unsimulated_placement_rates, unsimulated_counts, unsimulated_full_likelihood = SBM.bucket_extract(sorted_allocation, simulated_out, NUMBER_OF_TYPES, numtotal)
    println("$(sum(simulated_out)) total placements sampled")

    simulated_placement_rates = zeros(Int32, numtotal, NUMBER_OF_TYPES)
    simulated_counts = zeros(Int32, numtotal, NUMBER_OF_TYPES)

    # the structure of the departments is still the same, so reuse the old metrics
    @time simulated_est_obj, simulated_est_alloc = SBM.doit(simulated_out, simulated_placement_rates, simulated_counts, length(academic_list), length(acd_sink_list), length(gov_sink_list), length(pri_sink_list), length(tch_sink_list), length(institutions), NUMBER_OF_TYPES, numtotal, 500 * (NUMBER_OF_TYPES-2) + 1000)
    simulated_est_mat, simulated_est_count, simulated_full_likelihood = SBM.bucket_extract(simulated_est_alloc, simulated_out, NUMBER_OF_TYPES, numtotal)
    simulated_sorted_allocation, simulated_o = SBM.get_results(simulated_placement_rates, simulated_counts, simulated_est_mat, simulated_est_count, simulated_est_alloc, institutions, NUMBER_OF_TYPES, numtotal)

    for sorted_type in 1:NUMBER_OF_TYPES
        println("TYPE $sorted_type:")
        fullcounter = 0
        simulatedfullcounter = 0
        switchcounter = 0
        simulatedswitchcounter = 0
        for (i, sbm_type) in enumerate(sorted_allocation)
            simulated_type = simulated_sorted_allocation[i]
            if sorted_type == sbm_type # currently iterating type
                fullcounter += 1
                if simulated_type != sbm_type # the newly simulated type is different
                    println("  $(institutions[i]): $sbm_type -> $simulated_type")
                    switchcounter += 1
                end
            end
            if sorted_type == simulated_type # currently iterating type
                simulatedfullcounter += 1
                if simulated_type != sbm_type # the original type is different
                    println("  $(institutions[i]): $simulated_type <- $sbm_type")
                    simulatedswitchcounter += 1
                end
            end
        end
        println("$switchcounter original departments repositioned out")
        println("$simulatedswitchcounter new departments repositioned in")
        println("$fullcounter departments total in original allocation")
        println("$simulatedfullcounter departments total in new allocation")
        println("$(100*switchcounter/fullcounter)% of original departments repositioned out")
        println("$(100*simulatedswitchcounter/simulatedfullcounter)% of new departments repositioned in")
        println()
    end

    println("True Placement Rates:")
    display(tier_poisson_specification)
    println("Simulated Placement Rates under original type allocation:")
    display(unsimulated_placement_rates ./ unsimulated_counts)
    println("Simulated Placement Rates under simulation-estimated type allocation:")
    display(simulated_placement_rates ./ simulated_counts)
    println()
    
    println("True Placement Counts:")
    display(placement_rates)
    println("Simulated Placement Counts under original type allocation:")
    display(unsimulated_placement_rates)
    println("Simulated Placement Counts under simulation-estimated type allocation (this may look very different):")
    display(simulated_placement_rates)
    println()

    println("True Likelihood:")
    println(full_likelihood)
    println("Simulated Likelihood under original type allocation:")
    println(unsimulated_full_likelihood)
    println("Simulated Likelihood under simulation-estimated type allocation:")
    println(simulated_full_likelihood)
end

old_parameters_random_data()