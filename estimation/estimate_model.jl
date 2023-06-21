"""
Mapinator Model Parameter Estimator
James Yuming Yu, 1 May 2023
"""

using BlackBoxOptim, Distributions, ForwardDiff, Integrals, JSON, Optim, Random, StatsPlots, DelimitedFiles

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

function print_metrics(p_vec, m_vec, n_vec, n, m, T, S, placements, years)
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
    min_vec = zeros(T + 1)
    for i in 1:T-1
        packet = optimize(x -> (F_(x[1], p_vec, n_vec, n, T, S) - (Fx_vec[i] - ((m_vec[i] / pi_vec[i]) * (1.0 - (p_vec[i] ^ (1.0 / (n - 1.0))))))) ^ 2, [0.0], [1.0], [0.5], Fminbox(LBFGS()); autodiff = :forward)
        x_vec[i + 1] = Optim.minimizer(packet)[1] # there is no simple closed-form for F^{-1}(x) so this numerically computes x1, x2, x3
        min_vec[i + 1] = Optim.minimum(packet)[1]
    end
    
    objective = 0.0
    q_matrix = zeros((T, T))
    h_matrix = zeros(size(placements))
    nh_matrix = zeros(size(placements))
    for i in 1:size(placements)[1], t in 1:size(placements)[2]
        h_for_matrix = h_it_(p_vec, pi_vec, Fx_vec, m_vec, n_vec, x_vec, n, T, S, i, t)
        mean = n_vec[i] * years * h_for_matrix
        h_matrix[i, t] = h_for_matrix
        nh_matrix[i, t] = mean
        objective += (placements[i, t] - mean) ^ 2 / mean
    end
    
    for s in 1:T, t in 1:T
        q_for_matrix = Q_ts_(F_(x_vec[s], p_vec, n_vec, n, T, S), Fx_vec, pi_vec, m_vec, n, t, s)
        q_matrix[s, t] = q_for_matrix
    end

    for i in 1:T
        println("pi_", i, " = ", pi_vec[i])
    end
    println()
    for i in 1:T+1
        println("x_", i - 1, " = ", x_vec[i], " (error: ", min_vec[i], ")")
    end
    println()
    for i in 1:T
        println("F(x_", i - 1, ") = ", Fx_vec[i])
    end
    println()
    println("objective value = ", objective)
    println()
    println(n, " institutions")
    println("estimated n_i = ", round.(n_vec))
    println()
    println(m, " graudates")
    println("estimated m_i = ", round.(m_vec))
    println()
    println("estimated Q_t(x_s) (rows are offer value from high to low, columns are type in increasing type index:")
    for i in 1:size(q_matrix)[1]
        println(round.(q_matrix[i, :], digits = 4))
    end
    println()
    println("estimated h_it:")
    for i in 1:size(h_matrix)[1]
        println(round.(h_matrix[i, :], digits = 4))
    end
    println()
    println("estimated placement rates:")
    for i in 1:size(nh_matrix)[1]
        println(round.(nh_matrix[i, :], digits = 4))
    end
    println()
    println("actual placement rates:")
    for i in 1:size(placements)[1]
        println(placements[i, :])
    end
    println()
    println("difference between estimated and actual placement rates:")
    for i in 1:size(placements)[1]
        println(round.(nh_matrix[i, :] - placements[i, :], digits = 4))
    end
    println()
    println("chi-square p-value")
    println(1 - cdf(Chisq((size(placements)[1] - 1) * (size(placements)[2] - 1)), objective))
end

function main(; SEED=0)
    YEAR_INTERVAL = 2003:2021  # change this to select the years of data to include in the estimation
    NUMBER_OF_TYPES = 4        # change this to select the number of types to classify academic departments into
    NUMBER_OF_SINKS = 4        # this should not change unless you change the sink structure
    numtotal = NUMBER_OF_TYPES + NUMBER_OF_SINKS

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

    out, academic_list, acd_sink_list, gov_sink_list, pri_sink_list, tch_sink_list, sinks, institutions = SBM.get_placements(YEAR_INTERVAL, false)
    placement_rates = zeros(Int32, numtotal, NUMBER_OF_TYPES)
    counts = zeros(Int32, numtotal, NUMBER_OF_TYPES)
    Random.seed!(SEED) # re-seed after every round
    @time est_obj, est_alloc = SBM.doit(out, placement_rates, counts, length(academic_list), length(acd_sink_list), length(gov_sink_list), length(pri_sink_list), length(tch_sink_list), length(institutions), NUMBER_OF_TYPES, numtotal, 500 * (NUMBER_OF_TYPES-2) + 1000)
    est_mat, est_count, full_likelihood = SBM.bucket_extract(est_alloc, out, NUMBER_OF_TYPES, numtotal)
    sorted_allocation, o = SBM.get_results(placement_rates, counts, est_mat, est_count, est_alloc, institutions, NUMBER_OF_TYPES, numtotal)

    n = length(institutions)
    m = 1000 # just approximate for now.

    # all lower bounds are zero as these should be positive parameters
    res = bboptimize(p -> chisquare(p, NUMBER_OF_TYPES, NUMBER_OF_SINKS, placement_rates, Float64(length(YEAR_INTERVAL)), start_n, start_m, n, m), SearchRange = [(0.0, upper[i]) for i in eachindex(upper)], MaxFuncEvals = 200000, TraceInterval = 10)
    sol = best_candidate(res)

    n_vec = sol[start_n:start_n+numtotal-1]
    m_vec = sol[start_m:start_m+NUMBER_OF_TYPES-1]
    print_metrics(sol, m_vec, n_vec, n, m, NUMBER_OF_TYPES, NUMBER_OF_SINKS, placement_rates, Float64(length(YEAR_INTERVAL)))
    
    for i in 1:NUMBER_OF_TYPES-1
        println("v_", i + 1, "/v_", i, " = ", sol[i])
    end

    v_base = 1
    for i in 1:NUMBER_OF_TYPES
        println("v", i, ": ", v_base)
        if i != NUMBER_OF_TYPES
            v_base = sol[i] * v_base
        end
    end

    for select_type in 1:NUMBER_OF_TYPES
        println("mean for type ", select_type, ": ", mean(TruncatedNormal(sol[NUMBER_OF_TYPES-1+select_type], sol[NUMBER_OF_TYPES-1+select_type+numtotal], 0, 1)))
        println("stddev for type ", select_type, ": ", std(TruncatedNormal(sol[NUMBER_OF_TYPES-1+select_type], sol[NUMBER_OF_TYPES-1+select_type+numtotal], 0, 1)))
        println()
    end
    println("mean for sink: ", mean(TruncatedNormal(sol[NUMBER_OF_TYPES-1+numtotal], sol[NUMBER_OF_TYPES-1+numtotal+numtotal], 0, 1)))
    println("stddev for sink: ", std(TruncatedNormal(sol[NUMBER_OF_TYPES-1+numtotal], sol[NUMBER_OF_TYPES-1+numtotal+numtotal], 0, 1)))

    # https://github.com/JuliaPlots/StatsPlots.jl/blob/master/README.md
    # https://docs.juliaplots.org/latest/tutorial/

    select_type = 1
    cdfs = plot(TruncatedNormal(sol[NUMBER_OF_TYPES-1+select_type], sol[NUMBER_OF_TYPES-1+select_type+numtotal], 0, 1), func = cdf, title = "CDFs of Types", label = "Type 1")
    for select_type in 2:NUMBER_OF_TYPES # academic types
        plot!(cdfs, TruncatedNormal(sol[NUMBER_OF_TYPES-1+select_type], sol[NUMBER_OF_TYPES-1+select_type+numtotal], 0, 1), func = cdf, label = string("Type ", select_type))
    end

    for select_type in NUMBER_OF_TYPES+1:numtotal # sinks
        plot!(cdfs, TruncatedNormal(sol[NUMBER_OF_TYPES-1+select_type], sol[NUMBER_OF_TYPES-1+select_type+numtotal], 0, 1), func = cdf, label = string("Sink ", select_type - NUMBER_OF_TYPES))
    end
    xlabel!(cdfs, "offer value")
    ylabel!(cdfs, "F(offer value)")
    savefig(cdfs, "cdfs.png")

    select_type = 1
    pdfs = plot(TruncatedNormal(sol[NUMBER_OF_TYPES-1+select_type], sol[NUMBER_OF_TYPES-1+select_type+numtotal], 0, 1), func = pdf, title = "PDFs of Types", label = "Type 1")
    for select_type in 2:NUMBER_OF_TYPES # academic types
        plot!(pdfs, TruncatedNormal(sol[NUMBER_OF_TYPES-1+select_type], sol[NUMBER_OF_TYPES-1+select_type+numtotal], 0, 1), func = pdf, label = string("Type ", select_type))
    end

    for select_type in NUMBER_OF_TYPES+1:numtotal # sinks
        plot!(pdfs, TruncatedNormal(sol[NUMBER_OF_TYPES-1+select_type], sol[NUMBER_OF_TYPES-1+select_type+numtotal], 0, 1), func = pdf, label = string("Sink ", select_type - NUMBER_OF_TYPES))
    end
    xlabel!(pdfs, "offer value")
    ylabel!(pdfs, "f(offer value)")
    savefig(pdfs, "pdfs.png")
end

main()


#=

# unused code for deleting outliers from the pdf plot to improve readability

TYPE_TO_DELETE = 4 # change this if you want to remove the pdf of a different academic type; set to zero to not delete any
SINK_TO_DELETE = 0 # change this if you want to remove the pdf of a different sink type

select_type = 1
pdfs = plot(TruncatedNormal(sol[NUMBER_OF_TYPES-1+select_type], sol[NUMBER_OF_TYPES-1+select_type+numtotal], 0, 1), func = pdf, title = "PDFs of Types", label = "Type 1")
for select_type in 2:NUMBER_OF_TYPES # academic types
    if select_type != TYPE_TO_DELETE
        plot!(pdfs, TruncatedNormal(sol[NUMBER_OF_TYPES-1+select_type], sol[NUMBER_OF_TYPES-1+select_type+numtotal], 0, 1), func = pdf, label = string("Type ", select_type))
    end
end

for select_type in NUMBER_OF_TYPES+1:numtotal # sinks
    if select_type != SINK_TO_DELETE + NUMBER_OF_TYPES
        plot!(pdfs, TruncatedNormal(sol[NUMBER_OF_TYPES-1+select_type], sol[NUMBER_OF_TYPES-1+select_type+numtotal], 0, 1), func = pdf, label = string("Sink ", select_type - NUMBER_OF_TYPES))
    end
end
xlabel!(pdfs, "offer value")
ylabel!(pdfs, "f(offer value)")
pdfs
=#