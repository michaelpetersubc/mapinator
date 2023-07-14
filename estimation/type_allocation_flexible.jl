"""
flexible functions to augment type_allocation_base.jl with arbitrarily-generated sinks
"""

module SBM_flexible

include("type_allocation_base.jl")

using DataStructures, HTTP, JSON, Random

export doit, fetch_data, get_builders, get_adjacency, get_allocation, nice_table

function doit(sample, num_academic, sink_counters, numtier, numtotal, blankcount_tol)
    """
        Compute the maximum likelihood estimate of the type assignment via SBM applied to the data `sample`
    """
    
    # some initial states
    cur_objective = Inf
    T = zeros(Int32, numtotal, numtier)
    count = zeros(Int32, numtotal, numtier)

    blankcount = 0
    current_allocation = Vector{Int32}(undef, num_academic + sum(sink_counters))
    new_tier_lookup = [deleteat!(Vector(1:numtier), i) for i in 1:numtier]
    cursor = 1

    for _ in 1:num_academic
        current_allocation[cursor] = 1
        cursor += 1
    end

    for (i, num_sink) in enumerate(sink_counters)
        for _ in 1:num_sink
            current_allocation[cursor] = numtier + i # the sinks must stay in fixed types
            cursor += 1
        end
    end

    if numtier == 1 # if only one tier is required, we are already done
        return cur_objective, current_allocation
    end

    while true # BEGIN MONTE CARLO REALLOCATION: attempt to reallocate academic institutions to a random spot
        k = rand(1:num_academic)
        @inbounds old_tier = current_allocation[k]
        @inbounds current_allocation[k] = rand(new_tier_lookup[old_tier])
        # check if the new assignment is better
        test_objective = SBM.bucket_estimate(current_allocation, sample, T, count, numtier, numtotal)
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
            if blankcount % blankcount_tol == 0
                found = false
                for i in 1:num_academic, tier in 1:numtier
                    # conduct a single-department edit
                    @inbounds original = current_allocation[i]
                    @inbounds current_allocation[i] = tier
                    test_objective = SBM.bucket_estimate(current_allocation, sample, T, count, numtier, numtotal)
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

function api_to_placements(endpoint)
    """Sort the placement data from an API endpoint by placement year."""
    to_from_by_year = DefaultDict(Dict)
    api_data = HTTP.get(endpoint) # e.g. "https://support.econjobmarket.org/api/placement_data"
    to_from = JSON.parse(String(api_data.body))
    if "error" in keys(to_from)
        error(string(to_from["error"], ": ", to_from["error_description"]))
    end
    for placement in to_from
        to_from_by_year[string(placement["year"])][string(placement["aid"])] = placement
    end
    return to_from_by_year
end

function json_to_placements(endpoint)
    """Get placement data from a filepath."""
    return JSON.parsefile(endpoint) # e.g. "to_from_by_year.json"
end

function fetch_data(endpoint)
    """
        Get placement data from an arbitrary endpoint.
    """

    if startswith(endpoint, "http") # a URL
        return api_to_placements(endpoint)
    else
        return json_to_placements(endpoint) # a JSON file
    end
end

function get_builders(to_from_by_year, YEAR_INTERVAL)
    """
        Extract the placement outcomes occurring in YEAR_INTERVAL
    """

    institution_mapping = Dict()
    academic = Set()
    academic_to = Set()
    academic_builder = []
    rough_sink_builder = []

    for year in keys(to_from_by_year)
        if parse(Int32, year) in YEAR_INTERVAL
            # ASSUMPTION: every applicant ID has only one placement
            for (_, placement) in to_from_by_year[year]
                push!(academic, placement["from_institution_name"])
                institution_mapping[string(placement["from_institution_id"])] = placement["from_institution_name"]
                institution_mapping[string(placement["to_institution_id"])] = placement["to_name"]
                if placement["position_name"] == "Assistant Professor"
                    push!(academic_to, placement["to_name"])
                    push!(academic_builder, placement)
                else
                    push!(rough_sink_builder, placement)
                end
            end
        end
    end
    return academic, academic_to, academic_builder, rough_sink_builder, institution_mapping
end

function get_adjacency(academic_list, institutions, academic_builder, sink_builder; DEBUG = true, bootstrap_samples = 0)
    """
        Construct the adjacency matrix of placements.
    """

    out = zeros(Int32, length(institutions), length(academic_list))

    # if bootstrap sampling, only select a few placements
    # if not, this list will be empty (bootstrap_samples = 0)
    indices_to_include = rand(1:length(academic_builder)+length(sink_builder), bootstrap_samples)
    outcome_counter = 0

    if bootstrap_samples == 0
        for outcome in academic_builder
            outcome_counter += 1
            out[findfirst(isequal(outcome["to_name"]), institutions), findfirst(isequal(outcome["from_institution_name"]), institutions)] += 1
        end
        for (outcome_to_name, outcome) in sink_builder
            outcome_counter += 1
            out[findfirst(isequal(outcome_to_name), institutions), findfirst(isequal(outcome["from_institution_name"]), institutions)] += 1
        end
    else
        for index in indices_to_include
            if index <= length(academic_builder)
                outcome = academic_builder[index]
                outcome_counter += 1
                out[findfirst(isequal(outcome["to_name"]), institutions), findfirst(isequal(outcome["from_institution_name"]), institutions)] += 1
            else
                outcome_to_name, outcome = sink_builder[index - length(academic_builder)]
                outcome_counter += 1
                out[findfirst(isequal(outcome_to_name), institutions), findfirst(isequal(outcome["from_institution_name"]), institutions)] += 1
            end
        end
    end

    if DEBUG
        println("Total ", length(academic_builder)+length(sink_builder), " Placements (found ", outcome_counter, " by sequence counting, ", sum(out), " by matrix sum)")
        if bootstrap_samples != 0
            println(" bootstrapping ", bootstrap_samples, " samples")
        end
    end

    return out
end

function get_allocation(est_alloc, out, NUMBER_OF_TYPES, numtotal, institutions)
    """
        Compile the results of an SBM allocation.
    """

    placement_rates = zeros(Int32, numtotal, NUMBER_OF_TYPES)
    counts = zeros(Int32, numtotal, NUMBER_OF_TYPES)
    est_mat, est_count, full_likelihood = SBM.bucket_extract(est_alloc, out, NUMBER_OF_TYPES, numtotal)
    sorted_allocation, o = SBM.get_results(placement_rates, counts, est_mat, est_count, est_alloc, institutions, NUMBER_OF_TYPES, numtotal)
    return placement_rates, counts, sorted_allocation, full_likelihood
end

function nice_table(table, numtier, numsink, sink_labels)
    """Passthrough of SBM.nice_table()."""
    push!(sink_labels, "Column Totals")
    return SBM.nice_table(table, numtier, numsink, sink_labels)
end

end