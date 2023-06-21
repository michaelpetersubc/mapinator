"""
Mapinator Model Parameter Estimator with Bootstrap
James Yuming Yu, 21 June 2023
"""

using BlackBoxOptim, Distributions, ForwardDiff, Integrals, JSON, Optim, Random, StatsPlots, DelimitedFiles, FileIO

include("type_allocation_base.jl")

# define p_vec as
# [v2/v1 v3/v2 v4/v3 mu1 mu2 mu3 mu4 mus sg1 sg2 sg3 sg4 sgs]
# let T = 4
# let S = 1
# then p_vec[i + T - 1] = p_vec[i + 3] for i:1..5 gives mu
# then p_vec[i + T - 1 + T + S] = p_vec[i + 3 + 5] for i:1..5 gives sigma
# then p_vec[i] for i:1..3 gives vi/vj

# truncated normal: https://juliastats.org/Distributions.jl/stable/truncate/#Distributions.TruncatedNormal

function pi_t_(pi_t_minus_1, v_ratio_t, m_t_minus_1, m_t, n)
    return pi_t_minus_1 / (pi_t_minus_1 + ((v_ratio_t ^ (1 / (n - 1))) * m_t_minus_1 / m_t))
end

function F_x_t_(Fx_t_minus_1, pi_t, m_t, v_ratio_t, n)
    return Fx_t_minus_1 - ((m_t / pi_t) * (1 - (v_ratio_t ^ (1 / (n - 1)))))
end

function f_i_x_t_(x, p_vec, i, T, S)
    return pdf(TruncatedNormal(p_vec[i + T - 1], p_vec[i + T - 1 + T + S], 0, 1), x)
end

function F_(x, p_vec, n_vec, n, T, S)
    return sum([(n_vec[i] / n) * cdf(TruncatedNormal(p_vec[i + T - 1], p_vec[i + T - 1 + T + S], 0, 1), x) for i in 1:T+S])
end

function Q_ts_(Fx, Fx_vec, pi_vec, m_vec, n, t, s)
    # pi_vec = [1, pi2, pi3, ...]
    # Fx_vec = [1, Fx1, Fx2, ...]
    # Fx_vec[s] = F(x_{s-1})
    target = ((Fx_vec[s] - Fx) * pi_vec[t] * prod([(1.0 - pi_vec[i]) for i in t+1:s]) / m_vec[t]) 
    subtractor = sum([(Fx_vec[k] - Fx_vec[k + 1]) * pi_vec[t] * prod([(1.0 - pi_vec[i]) for i in t+1:k]) / m_vec[t] for k in t:s-1])
    return (1.0 - target - subtractor) ^ (n - 1.0)
end

function h_it_(p_vec, pi_vec, Fx_vec, m_vec, n_vec, x_vec, n, T, S, i, t)
    # x_vec = [x0, x1, x2, ...]
    # x_vec[s] = x_{s-1}
    return sum([pi_vec[t] * prod([(1.0 - pi_vec[j]) for j in t+1:s]) * solve(IntegralProblem((x, p) -> Q_ts_(F_(x, p, n_vec, n, T, S), Fx_vec, pi_vec, m_vec, n, t, s) * f_i_x_t_(x, p, i, T, S), x_vec[s + 1], x_vec[s], p_vec), HCubatureJL())[1] for s in t:T])
end

# at one point this method was based on 
# https://discourse.julialang.org/t/a-hacky-guide-to-using-automatic-differentiation-in-nested-optimization-problems/39123
# though has since evolved to not use autodifferentiation in the outer optimizer, which turns out to be faster

# optimization reference: https://julianlsolvers.github.io/Optim.jl/stable/#user/minimization/
# this reference also references the global minimizer used for the outer optimizer: 
# https://github.com/robertfeldt/BlackBoxOptim.jl
function chisquare(p_vec, T, S, placements, years, start_n, start_m, n, m)
    n_vec = p_vec[start_n:start_n+T+S-1]
    m_vec = p_vec[start_m:start_m+T-1]
    n_vec = n * n_vec / sum(n_vec)
    m_vec = m * m_vec / sum(m_vec)
    pi_vec = ones(T)
    Fx_vec = ones(T)
    for t in 2:T
        pi_vec[t] = pi_t_(pi_vec[t - 1], p_vec[t - 1], m_vec[t - 1], m_vec[t], n) 
        # note pi_vec = [pi1 = 1, pi2, pi3, pi4] but Fx_vec = [Fx0 = 1, Fx1, Fx2, Fx3] 
        Fx_vec[t] = F_x_t_(Fx_vec[t - 1], pi_vec[t - 1], m_vec[t - 1], p_vec[t - 1], n)
    end
    
    x_vec = ones(T + 1) # x_vec = [x0 = 1, x1, x2, x3, x4 = 0]
    x_vec[T + 1] = 0.0
    for i in 1:T-1
        packet = optimize(x -> (F_(x[1], p_vec, n_vec, n, T, S) - (Fx_vec[i] - ((m_vec[i] / pi_vec[i]) * (1.0 - (p_vec[i] ^ (1.0 / (n - 1.0))))))) ^ 2, [0.0], [1.0], [0.5], Fminbox(LBFGS()); autodiff = :forward)
        x_vec[i + 1] = Optim.minimizer(packet)[1] # there is no simple closed-form for F^{-1}(x) so this numerically computes x1, x2, x3
    end
    
    objective = 0.0
    # TODO: div by zero and negative floating point in mean
    for i in 1:size(placements)[1], t in 1:size(placements)[2]
        mean = n_vec[i] * years * h_it_(p_vec, pi_vec, Fx_vec, m_vec, n_vec, x_vec, n, T, S, i, t)
        objective += (placements[i, t] - mean) ^ 2 / mean
    end
    return objective
end

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
    likelihood_store = zeros(BOOTSTRAP_ROUNDS)
    sol_store = Vector{Any}(undef, BOOTSTRAP_ROUNDS)
    n_store = zeros(BOOTSTRAP_ROUNDS)
    m_store = zeros(BOOTSTRAP_ROUNDS)

    # upper bound on the value ratios, which should all be less than 1
    # if any ratio turns out to be 1.0 or close to it at optimality, this could indicate that a lower tier has a higher value than a higher one
    upper = [1.0 for i in 1:NUMBER_OF_TYPES-1] 

    # upper bound on the mu parameter of truncated normal, which is strictly within [0, 1] as the mean is greater than mu in truncated normal
    append!(upper, [1.0 for i in 1:numtotal])

    # reasonable upper bound on the sigma parameter of truncated normal
    # if any parameter estimate is close to this at optimality, make the upper bound higher
    append!(upper, [10.0 for i in 1:numtotal])

    # n_i
    start_n = length(upper) + 1
    append!(upper, [2000.0 for i in 1:numtotal])

    # m_i
    start_m = length(upper) + 1
    append!(upper, [2000.0 for i in 1:NUMBER_OF_TYPES])

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
        likelihood_store[i] = full_likelihood

        println("  Commencing round $i value estimation on thread $(Threads.threadid())")
        n = length(institutions)
        m = 1000 # just approximate for now.

        # all lower bounds are zero as these should be positive parameters
        res = bboptimize(p -> chisquare(p, NUMBER_OF_TYPES, NUMBER_OF_SINKS, placement_rates, Float64(length(YEAR_INTERVAL)), start_n, start_m, n, m), SearchRange = [(0.0, upper[i]) for i in eachindex(upper)], MaxFuncEvals = 100000, TraceMode = :silent)
        sol = best_candidate(res)
        sol_store[i] = sol
        n_store[i] = n
        m_store[i] = m

        println("  Completed round $i on thread $(Threads.threadid())")
    end
    bootstrap_output = Dict("placement_rates" => est_mat_store, "placement_counts" => est_count_store, "type_allocation" => est_alloc_store, "dept_labels" => institutions_store, "likelihoods" => likelihood_store, "model_estimates" => sol_store, "n" => n_store, "m" => m_store, "NUMBER_OF_TYPES" => NUMBER_OF_TYPES, "NUMBER_OF_SINKS" => NUMBER_OF_SINKS, "YEAR_INTERVAL" => YEAR_INTERVAL, "BOOTSTRAP_SAMPLE_SIZE" => BOOTSTRAP_SAMPLE_SIZE, "BOOTSTRAP_ROUNDS" => BOOTSTRAP_ROUNDS, "upper" => upper, "SEED" => SEED)
    mkpath(".estimates")
    save(".estimates/model_bootstrap_output.jld2", bootstrap_output)
end

main()
    