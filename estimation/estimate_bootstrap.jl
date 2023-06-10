using FileIO, Random

include("type_allocation_base.jl")

function main(; SEED=0)
    YEAR_INTERVAL = 2003:2021  # change this to select the years of data to include in the estimation
    NUMBER_OF_TYPES = 4        # change this to select the number of types to classify academic departments into
    NUMBER_OF_SINKS = 4        # this should not change unless you change the sink structure
    numtotal = NUMBER_OF_TYPES + NUMBER_OF_SINKS
    out, academic_list, acd_sink_list, gov_sink_list, pri_sink_list, tch_sink_list, sinks, institutions = SBM.get_placements(YEAR_INTERVAL, false)
    BOOTSTRAP_SAMPLE_SIZE = sum(out) # change this to make the number of bootstrap samples larger or smaller than the true samples
    BOOTSTRAP_ROUNDS = 40      # change this to select the number of times to re-generate the placement rates

    est_mat_store = zeros(numtotal, NUMBER_OF_TYPES, BOOTSTRAP_ROUNDS)
    est_count_store = zeros(numtotal, NUMBER_OF_TYPES, BOOTSTRAP_ROUNDS)
    est_alloc_store = zeros(length(institutions), BOOTSTRAP_ROUNDS)
    institutions_store = Array{String}(undef, length(institutions), BOOTSTRAP_ROUNDS)
    Random.seed!(SEED) # do not re-seed inside the for loop or else the bootstrap calls will not be different between rounds

    Threads.@threads for i in 1:BOOTSTRAP_ROUNDS
        println("Commencing round $i on thread $(Threads.threadid())")
        out, academic_list, acd_sink_list, gov_sink_list, pri_sink_list, tch_sink_list, sinks, institutions = SBM.get_placements(YEAR_INTERVAL, false; bootstrap_samples = BOOTSTRAP_SAMPLE_SIZE)
        placement_rates = zeros(Int32, numtotal, NUMBER_OF_TYPES)
        counts = zeros(Int32, numtotal, NUMBER_OF_TYPES)
        
        @time est_obj, est_alloc = SBM.doit(out, placement_rates, counts, length(academic_list), length(acd_sink_list), length(gov_sink_list), length(pri_sink_list), length(tch_sink_list), length(institutions), NUMBER_OF_TYPES, numtotal, 500 * (NUMBER_OF_TYPES-2) + 1000)
        est_mat, est_count, full_likelihood = SBM.bucket_extract(est_alloc, out, NUMBER_OF_TYPES, numtotal)
        sorted_allocation, o = SBM.get_results(placement_rates, counts, est_mat, est_count, est_alloc, institutions, NUMBER_OF_TYPES, numtotal)
        est_mat_store[:, :, i] = placement_rates ./ counts
        est_count_store[:, :, i] = placement_rates
        est_alloc_store[:, i] = sorted_allocation
        institutions_store[:, i] = institutions
        println("  Completed round $i on thread $(Threads.threadid())")
    end

    bootstrap_output = Dict("placement_rates" => est_mat_store, "placement_counts" => est_count_store, "type_allocation" => est_alloc_store, "dept_labels" => institutions_store)
    mkpath(".estimates")
    save(".estimates/bootstrap_output.jld2", bootstrap_output)
end

main()