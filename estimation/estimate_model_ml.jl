"""
Mapinator Model Parameter Estimator with Maximum Likelihood
James Yuming Yu, 16 September 2023
"""

using BlackBoxOptim, Distributions, ForwardDiff, Integrals, JSON, Roots, Optim, Random, StatsPlots, DelimitedFiles

include("type_allocation_base.jl")

# define p_vec as e.g.
# [v2/v1 v3/v2 v4/v3 α1 α2 α3 α4 mu1 mu2 mu3 mu4 mus sg1 sg2 sg3 sg4 sgs]

# truncated normal: https://juliastats.org/Distributions.jl/stable/truncate/#Distributions.TruncatedNormal

function F(x, ρ, μ, σ, K)
    return sum([ρ[i] * cdf(TruncatedNormal(μ[i], σ[i], 0, 1), x) for i in 1:K])
end

function f(x, ρ, μ, σ, K)
    return sum([ρ[i] * pdf(TruncatedNormal(μ[i], σ[i], 0, 1), x) for i in 1:K])
end

function G(Fim1, Fx, αsum)
    return (Fim1 - Fx) / αsum
end

function κ(i, t, v_rel)
    return sum([-log(v_rel[j]) for j in t:i-1])
end

function fi(x, μ, σ)
    return pdf(TruncatedNormal(μ, σ, 0, 1), x)
end

function q(i, t, Fx_vec, x_vec, ρ, μ, σ, α, v_rel, k, K)
    # Fx_vec = [F(x0)=1, F(x1), F(x2), F(x3), ..., F(xk-1)]
    # x_vec = [x0 = 1, x1, x2, x3, ..., xk = 0]
    # x_vec[s] = x_{s-1}, so the limits of integration are and must be offset by 1 below
    # TODO: can some integrals be cached as a speed-up? can some integrals be computed in parallel?
    return sum([(α[t]/sum(α[1:s])) * solve(IntegralProblem{false}((x, p) -> exp(-(G(Fx_vec[s], F(x, ρ, μ, σ, K), sum(α[1:s])) + κ(s, t, v_rel))) * fi(x, μ[i], σ[i]), x_vec[s+1], x_vec[s]), HCubatureJL())[1] for s in t:k])
end

function Fx(t, α, v_rel)
    return 1 - sum([-log(v_rel[j])*sum(α[1:j]) for j in 1:t])
end

function Q2(ratio, β)
    return β * (1 - exp(-ratio)) / ratio
end

function estimate_likelihood(p_vec, placements, k, K, M)
    v_rel = p_vec[1:k-1]
    α = p_vec[k:2k-1] / sum(p_vec[k:2k-1])
    μ = p_vec[2k:2k+K-1]
    σ = p_vec[2k+K:2k+2K-1]
    ρ = p_vec[2k+2K:2k+3K-1] / sum(p_vec[2k+2K:2k+3K-1])
    β = p_vec[end]
    
    Fx_vec = ones(k) # sets F(x0) = 1 by default; Fx_vec = [F(x0)=1, F(x1), F(x2), F(x3), ..., F(xk-1)]
    x_vec = ones(k+1) # x_vec = [x0 = 1, x1, x2, x3, ..., xk = 0]
    x_vec[k+1] = 0.0
    for t in 1:k-1
        Fx_vec_candidate = Fx(t, α, v_rel)
        if Fx_vec_candidate <= 0.0 # TODO: if this case occurs, can we speed up q()?
            Fx_vec[t+1:k] .= 0.0
            x_vec[t+1:k] .= 0.0
            break
        end
        Fx_vec[t+1] = Fx_vec_candidate
        # there is no simple closed-form for F^{-1}(x) so this numerically computes x1, x2, x3
        x_vec[t+1] = find_zero(x -> F(x, ρ, μ, σ, K) - Fx_vec[t+1], 0.5) 
    end

    objective = 0.0
    normalizer = 0.0

    q_it = zeros(K, k)
    for i in 1:K
        for t in 1:k
            prob = q(i, t, Fx_vec, x_vec, ρ, μ, σ, α, v_rel, k, K)
            q_it[i, t] = prob
            normalizer += ρ[i] * prob
        end
    end

    # TODO: div by zero and negative floating point in mean
    D = sum([ρ[i] * (1 - sum([q_it[i, t] for t in 1:k])) for i in 1:K])
    S = sum([α[t] * (1 - sum([ρ[i]*q_it[i, t] for i in 1:K])) for t in 1:k])
    for i in 1:K
        for t in 1:k
            prob = (1 - sum([q_it[i, s] for s in 1:k])) * Q2(D/S, β) * α[t] * (1 - sum([ρ[j] * q_it[j, t] for j in 1:K])) / S
            # println(sum([q_it[i, s] for s in 1:k]))
            # println(t, " ", i, " ", ρ[i] * (q_it[i, t] + prob), " ", ρ[i], " ", q_it[i, t], " ", (1 - sum([q_it[i, s] for s in 1:k])), " ", Q2(D/S, β), " ", α[t], " ", (1 - sum([ρ[j] * q_it[j, t] for j in 1:K])), " ", S, " ", prob)
            objective += placements[i, t] * (log(ρ[i] * (q_it[i, t] + prob)))
            normalizer += ρ[i] * prob
        end
    end
    
    objective -= M * log(normalizer)
    return -objective
end

function pi(t, α)
    return α[t] / sum(α[1:t])
end

function print_metrics(p_vec, placements, k, K, M)
    v_rel = p_vec[1:k-1]
    α = p_vec[k:2k-1] / sum(p_vec[k:2k-1])
    μ = p_vec[2k:2k+K-1]
    σ = p_vec[2k+K:2k+2K-1]
    ρ = p_vec[2k+2K:2k+3K-1] / sum(p_vec[2k+2K:2k+3K-1])
    β = p_vec[end]

    Fx_vec = ones(k)
    x_vec = ones(k+1)
    x_vec[k+1] = 0.0
    for t in 1:k-1
        Fx_vec_candidate = Fx(t, α, v_rel)
        if Fx_vec_candidate <= 0.0
            Fx_vec[t+1:k] .= 0.0
            x_vec[t+1:k] .= 0.0
            break
        end
        Fx_vec[t+1] = Fx_vec_candidate
        x_vec[t+1] = find_zero(x -> F(x, ρ, μ, σ, K) - Fx_vec[t+1], 0.5) 
    end

    objective = 0.0
    likelihood = 0.0
    normalizer = 0.0
    
    q_it = zeros(K, k)
    for i in 1:K, t in 1:k
        prob = q(i, t, Fx_vec, x_vec, ρ, μ, σ, α, v_rel, k, K)
        q_it[i, t] = prob
        normalizer += ρ[i] * prob
    end
    
    # TODO: div by zero and negative floating point in mean
    D = sum([ρ[i] * (1 - sum([q_it[i, t] for t in 1:k])) for i in 1:K])
    S = sum([α[t] * (1 - sum([ρ[i]*q_it[i, t] for i in 1:K])) for t in 1:k])
    round_2 = zeros(K, k)
    round_2_hiring = zeros(K, k)

    for i in 1:K, t in 1:k
        prob = (1 - sum([q_it[i, s] for s in 1:k])) * Q2(D/S, β) * α[t] * (1 - sum([ρ[j] * q_it[j, t] for j in 1:K])) / S
        round_2[i, t] = prob
        round_2_hiring[i, t] = Q2(D/S, β) * α[t] * (1 - sum([ρ[j] * q_it[j, t] for j in 1:K])) / S
        normalizer += ρ[i] * prob
    end

    round_1_failure = zeros(K)
    for i in 1:K
        round_1_failure[i] = (1 - sum([q_it[i, s] for s in 1:k]))
    end
    
    exp_placements_round_1 = zeros(K, k)
    exp_placements_round_2 = zeros(K, k)
    exp_placements = zeros(K, k)
    for i in 1:K, t in 1:k 
        expectation = M * (ρ[i] * (q_it[i, t] + round_2[i, t]) / normalizer)
        exp_placements_round_1[i, t] = M * (ρ[i] * q_it[i, t] / normalizer)
        exp_placements_round_2[i, t] = M * (ρ[i] * round_2[i, t] / normalizer)
        exp_placements[i, t] = expectation
        objective += (placements[i, t] - expectation) ^ 2 / expectation
        likelihood += placements[i, t] * (log(ρ[i] * (q_it[i, t] + round_2[i, t])))
        likelihood -= log(factorial(big(placements[i, t])))
    end
    likelihood -= M * log(normalizer)

    println("chi-square objective value = ", objective)
    println("log-likelihood objective value = ", likelihood)
    println("likelihood objective value = ", exp(likelihood))
    println("success sample size (departments) = ", M)
    println("estimated total samples (departments) = ", M / normalizer)
    println("estimated unmatched departments = ", (M / normalizer) - M)
    println("probability of any success: ", normalizer)
    println("probability of no success: ", 1 - normalizer)
    println("measure of departments in round 2 = ", D)
    println("measure of graduates in round 2 = ", S)
    println()
    println("predicted fraction of departments of each tier:")
    display(ρ)
    println()
    println("fractions observed among successful departments in data:")
    display(sum(placements, dims = 2) ./ M)
    println()

    for i in 1:k
        println("pi_", i, " = ", pi(i, α))
    end
    println()

    offer_targets = zeros(k, k)
    for t in 1:k, j in 1:t
        offer_targets[t, j] = pi(j, α) * prod([1 - pi(i, α) for i in j+1:t])
    end
    println("Tier selection probabilities for making offers:")
    display(offer_targets)
    println()

    println("Round 1 hiring probabilities:")
    display(q_it)
    println()

    println("Probabilities of failing round 1")
    display(round_1_failure)
    println()

    println("Probabilities of failing round 1 and hiring in round 2:")
    display(round_2)
    println()

    println("Round 2 hiring probabilities:")
    display(round_2_hiring)
    println()

    for i in 1:k+1
        println("x_", i - 1, " = ", x_vec[i])
    end
    println()
    for i in 1:k
        println("F(x_", i - 1, ") = ", Fx_vec[i])
    end
    println()
    for i in 1:k
        println("α_", i, " = ", α[i])
        println("  Est. graduates: ", α[i] * (M / normalizer - 1))
        println("  Successful: ", sum(placements[:, i]))
        println("  Unsuccessful: ", (α[i] * (M / normalizer - 1)) - sum(placements[:, i]))
    end
    println("Total estimated graduates: ", sum(α) * (M / normalizer - 1))
    println("Total successful graduates: ", M)
    println("Total estimated unsuccessful graduates: ", (sum(α) * (M / normalizer - 1)) - M)
    println("β = ", β)
    println()
    println("estimated placement rates, round 1 only:")
    display(exp_placements_round_1)
    println()
    println("estimated placement rates, round 2 only:")
    display(exp_placements_round_2)
    println()
    println("estimated placement rates, cumulative:")
    display(exp_placements)
    println()
    println("actual placement rates:")
    display(placements)
    println()
    println("difference between estimated and actual placement rates:")
    display(exp_placements - placements)
    println()
    println("chi-square p-value")
    println(1 - cdf(Chisq((size(placements)[1] - 1) * (size(placements)[2] - 1)), objective))
end

function main(; SEED=0)
    NUMBER_OF_TYPES = 4        # change this to select the number of types to classify academic departments into
    NUMBER_OF_SINKS = 4        # this should not change unless you change the sink structure
    numtotal = NUMBER_OF_TYPES + NUMBER_OF_SINKS
    Random.seed!(0)
    # the year interval is always 2003:2021 using estimate_parameters; change the function to adjust
    #println("Running SBM...")
    #@time res = SBM.estimate_parameters(NUMBER_OF_TYPES, 500 * (NUMBER_OF_TYPES-2) + 1000; SEED=0, DEBUG=false)
    #println("  SBM Complete with likelihood $(res.likelihood)")
    #println(res.placements)
    #println()

    res = (;placements = [496 66 33 3; 455 196 84 12; 725 618 363 43; 84 148 83 63; 126 66 41 29; 359 258 131 34; 447 206 94 18; 394 523 508 143])

    k = NUMBER_OF_TYPES
    K = numtotal
    M = sum(res.placements)

    # upper bound on the value ratios, which should all be less than 1
    # if any ratio turns out to be 1.0 or close to it at optimality, this could indicate that a lower tier has a higher value than a higher one
    upper = [1.0 for _ in 1:k-1] 

    # upper bound on variables proportionate to alpha
    append!(upper, [1.0 for _ in 1:k])

    # upper bound on the mu parameter of truncated normal, which is strictly within [0, 1] as the mean is greater than mu in truncated normal
    append!(upper, [1.0 for _ in 1:K])

    # upper bound on the sigma parameter of truncated normal
    append!(upper, [5.0 for _ in 1:K])

    # upper bound on variables proportionate to rho
    append!(upper, [1.0 for _ in 1:K])

    # upper bound on beta friction parameter
    push!(upper, 1.0)

    # all lower bounds are zero as these should be positive parameters
    sol_res = bboptimize(p -> estimate_likelihood(p, res.placements, k, K, M), SearchRange = [(0.0, upper[i]) for i in eachindex(upper)], MaxFuncEvals = 100000, TraceInterval = 5)
    sol = best_candidate(sol_res)

    print_metrics(sol, res.placements, k, K, M)
    
    for i in 1:k-1
        println("v_", i + 1, "/v_", i, " = ", sol[i])
    end

    v_base = 1
    for i in 1:k
        println("v", i, ": ", v_base)
        if i != k
            v_base = sol[i] * v_base
        end
    end

    for select_type in 1:k
        println("mean for type ", select_type, ": ", mean(TruncatedNormal(sol[2k-1+select_type], sol[2k-1+select_type+K], 0, 1)))
        println("stddev for type ", select_type, ": ", std(TruncatedNormal(sol[2k-1+select_type], sol[2k-1+select_type+K], 0, 1)))
        println()
    end
    for select_type in k+1:K
        println("mean for sink ", select_type - k, ": ", mean(TruncatedNormal(sol[2k-1+select_type], sol[2k-1+select_type+K], 0, 1)))
        println("stddev for sink ", select_type - k, ": ", std(TruncatedNormal(sol[2k-1+select_type], sol[2k-1+select_type+K], 0, 1)))
        println()
    end

    # https://github.com/JuliaPlots/StatsPlots.jl/blob/master/README.md
    # https://docs.juliaplots.org/latest/tutorial/
    
    select_type = 1
    cdfs = plot(TruncatedNormal(sol[2k-1+select_type], sol[2k-1+select_type+K], 0, 1), func = cdf, title = "CDFs of Types", label = "Type 1")
    for select_type in 2:NUMBER_OF_TYPES # academic types
        plot!(cdfs, TruncatedNormal(sol[2k-1+select_type], sol[2k-1+select_type+K], 0, 1), func = cdf, label = string("Type ", select_type))
    end

    for select_type in k+1:K # sinks
        plot!(cdfs, TruncatedNormal(sol[2k-1+select_type], sol[2k-1+select_type+K], 0, 1), func = cdf, label = string("Sink ", select_type - k))
    end
    xlabel!(cdfs, "offer value")
    ylabel!(cdfs, "F(offer value)")
    savefig(cdfs, "cdfs_mle.png")

    select_type = 1
    pdfs = plot(TruncatedNormal(sol[2k-1+select_type], sol[2k-1+select_type+K], 0, 1), func = pdf, title = "PDFs of Types", label = "Type 1")
    for select_type in 2:k # academic types
        plot!(pdfs, TruncatedNormal(sol[2k-1+select_type], sol[2k-1+select_type+K], 0, 1), func = pdf, label = string("Type ", select_type))
    end

    for select_type in k+1:K # sinks
        plot!(pdfs, TruncatedNormal(sol[2k-1+select_type], sol[2k-1+select_type+K], 0, 1), func = pdf, label = string("Sink ", select_type - k))
    end
    xlabel!(pdfs, "offer value")
    ylabel!(pdfs, "f(offer value)")
    savefig(pdfs, "pdfs_mle.png")
    
end

main()
