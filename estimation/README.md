## Accelerated SBM Sampler

Run the script using `julia --project -e 'using Pkg; Pkg.instantiate()'` followed by `julia --project --threads auto -O3 type_allocation.jl`.

The accelerated sampler in `type_allocation.jl` combines several optimizations for the original SBM procedure. These can be grouped into three categories:

### Likelihood Function Unrolling

The functional form of the likelihood function is:

$$log(\mathcal{L}(\lambda_{t_i, t_j, \forall i, j})) = \sum\limits_{i = 1}^{M}\sum\limits_{j = 1}^{N} log(\text{Pr}(Pois(\lambda_{t_i, t_j} = \hat A_{i, j})))$$

See [here](https://github.com/jbrightuniverse/EJM-Project/blob/main/assignment.pdf) for detailed definitions of variables used in these expressions. $M$ is the number of academic departments, $N$ is the total number of departments, $A$ is the placement rates adjacency matrix where $A_{i,j}$ is the placement rate for department $i$ to department $j$, $K$ is the number of total types, $t_i$ is the type of department $i$, and $\lambda_{t_i, t_j}$ is the mean placement rate for an arbitrary department of type $t_i$ to an arbitrary department of type $t_j$.

We can rewrite this using the definition of the Poisson random variable PMF as:

$$\sum\limits_{i = 1}^{M}\sum\limits_{j = 1}^{N} log(\frac{\lambda_{t_i, t_j}^{\hat A_{i, j}} e^{-\lambda_{t_i, t_j}}}{\hat A_{i, j}!})))$$

Given that log products and quotients can separate, that exponents can factor out, and that $log(e) = 1$, we can further rewrite this as:

$$\sum\limits_{i = 1}^{M}\sum\limits_{j = 1}^{N} [\hat A_{i, j} log(\lambda_{t_i, t_j}) -\lambda_{t_i, t_j} - log(\hat A_{i, j}!)]$$

From here, we use a method inspired by Karrer & Newman (2011) to perform a monotone transformation of the likelihood function which preserves the optimal solution parameters while reducing complexity. First, we recognize that if we change the parameters $\lambda$ between rounds, $\hat A$ never changes. This means that $log(\hat A_{i, j}!)$ is always constant with respect to all $\lambda$ variables.

Since summations are linear, we rewrite the expression as:

$$\sum\limits_{i = 1}^{M}\sum\limits_{j = 1}^{N} \hat A_{i, j} log(\lambda_{t_i, t_j}) -\sum\limits_{i = 1}^{M}\sum\limits_{j = 1}^{N} \lambda_{t_i, t_j} - \sum\limits_{i = 1}^{M}\sum\limits_{j = 1}^{N} log(\hat A_{i, j}!)$$

and now we can see that the term at the end is constant, so can be dropped without altering the optimal solution parameters:

$$log(\mathcal{\tilde L}(\lambda_{t_i, t_j, \forall i, j})) = \sum\limits_{i = 1}^{M}\sum\limits_{j = 1}^{N} \hat A_{i, j} log(\lambda_{t_i, t_j}) -\sum\limits_{i = 1}^{M}\sum\limits_{j = 1}^{N} \lambda_{t_i, t_j}$$

Next, recall that $\lambda_{t_i, t_j}$ is the mean placement rate i.e. the sum of all the placements from $t_i$ to $t_j$ collectively, divided by both the number of departments of type $t_i$ and the number of departments of type $t_j$. 

Let $M_i = N_i = |\{j: t_i = t_j\}|, i \in [1, K]$ be the number of departments of type $i$ such that, when defining $N_{K+1} = |\{j: t_{K+1} = t_j\}|$, we have $\sum\limits_{i}^{M_i} = M$ and $\sum\limits_{i}^{N_i} = N$. In other words, for the sink type $K+1$ (using 1 sink tier here instead of 4 from the note), $M_{K+1}$ is not defined and $N_{K+1}$ is.

We can then write $\lambda_{a, b}$ as:

$$\lambda_{a, b} = \frac{\sum\limits_{i = 1, t_i = a}^{M}\sum\limits_{j = 1, t_j = b}^{N} \hat A_{i, j}}{M_a N_b}$$

Next, $\sum\limits_{i = 1}^{M}\sum\limits_{j = 1}^{N} \lambda_{t_i, t_j}$ rewrites as the following partial sums:

$$\sum\limits_{a = 1}^{K}\sum\limits_{b = 1}^{K+1}\sum\limits_{i = 1, t_i = a}^{M} \sum\limits_{j = 1, t_j = b}^{N} \lambda_{t_i, t_j}$$

Now, if we examine $\sum\limits_{i = 1, t_i = a}^{M} \sum\limits_{j = 1, t_j = b}^{N} \lambda_{t_i, t_j}$, we see that $t_i = a$ and $t_j = b$ are constant.

Given that $M_a$ is the number of departments of type $a$ and $N_b$ is the number of departments of type $b$ as defined earlier, this inner double sum rewrites as:

$$M_a N_b \lambda_{a, b}$$

Which, using the definition of $\lambda$ above, simplifies to:

$$\sum\limits_{i = 1, t_i = a}^{M}\sum\limits_{j = 1, t_j = b}^{N} \hat A_{i, j}$$

and so we can rewrite $\sum\limits_{i = 1}^{M}\sum\limits_{j = 1}^{N} \lambda_{t_i, t_j}$ as the following:

$$\sum\limits_{a = 1}^{K}\sum\limits_{b = 1}^{K+1}\sum\limits_{i = 1, t_i = a}^{M}\sum\limits_{j = 1, t_j = b}^{N} \hat A_{i, j}$$

Finally, if we merge the partial sums back together, we get:

$$\sum\limits_{i = 1}^{M}\sum\limits_{j = 1}^{N} \lambda_{t_i, t_j} = \sum\limits_{i = 1}^{M}\sum\limits_{j = 1}^{N} \hat A_{i, j}$$

which is just the sum of all the entries of $A$, which is a constant independent of any $\lambda$ variable. Thus, this term can also be dropped from the likelihood function and we are left with:

$$log(\mathcal{\tilde{\tilde L}}(\lambda_{t_i, t_j, \forall i, j})) = \sum\limits_{i = 1}^{M}\sum\limits_{j = 1}^{N} \hat A_{i, j} log(\lambda_{t_i, t_j})$$

Finally, the algorithm itself keeps track of the numerator of $\lambda_{t_i, t_j}$ as a separate variable for efficiency purposes. Define:

$$T_{a,b} = \sum\limits_{i = 1, t_i = a}^{M}\sum\limits_{j = 1, t_j = b}^{N} \hat A_{i, j}$$

such that $\lambda_{a, b} = \frac{T_{a, b}}{M_a N_b}$. 

We can rewrite the double sum into partial sums as:

$$\sum\limits_{a = 1}^{K}\sum\limits_{b = 1}^{K+1}\sum\limits_{i = 1, t_i = a}^{M}\sum\limits_{j = 1, t_j = b}^{N} \hat A_{i, j} log(\lambda_{a, b})$$

Which then simplifies to the following given that $log(\lambda_{a, b})$ is independent of $i$ and $j$ and can thus move outside of the rightmost two sums:

$$log(\mathcal{\tilde{\tilde{\tilde L}}}(\lambda_{t_i, t_j, \forall i, j})) \sum\limits_{a = 1}^{K}\sum\limits_{b = 1}^{K+1} T_{a,b} log(\frac{T_{a,b}}{M_a N_b})$$

This is the setup in use in the current version of the algorithm. Given that $K$ is much smaller than $M$ or $N$, this transformed version of the likelihood takes significantly less time to compute than the original.

As an aside, we can use log rules to get the following:

$$log(\prod\limits_{a = 1}^K \prod\limits_{b = 1}^{K+1} \lambda_{a,b}^{T_{a,b}})$$

which shows that the objective function is actually just the product of the means corresponding to every placement in $A$, since $T_{a,b}$ is the number of total placements in $A$ that go from type $a$ to type $b$ departments.

If we look at the original product of Poisson PMFs which forms the likelihood, that result is what occurs when one takes that PMF, removes the denominator (which was proven constant), removes the exponential term (also proven constant) and merges common $\lambda$ variables via the $A_{i,j}$ exponents, given that $T_{a,b}$ is the sum of placements in $A_{i,j}$ with common $t_i$ and $t_j$ types.

### Early-Stopping: Search Thread Termination

Given that the likelihood computation is now more efficient, it has become viable to conduct a thorough validation of the existence of further likelihood improvements after a certain period of search time.

After sufficiently many periods of no improvements (which increases in the number of types), it is often a good guess that the algorithm is either close to or exactly unable to make any further optimizations.

The early-stopping procedure, to implement this guess, attempts to reallocate, in sequence, every department to every possible tier. This is the full set of possible reallocations given the current allocation.

If none of these reallocations produce a likelihood improvement, then we know with certainty that no further improvements are possible, so we can stop searching without having to wait for 30,000 reallocations as before.

### Candidate Cache

Originally, this line of code was in use: `@inbounds new_tier = rand(delete!(Set(1:num), old_tier))`.

This line was used to, given the original tier of a department, uniformly select a new tier to assign the department to. To do this, the line takes the set of all tiers, removes the original tier from the set, and then uniformly samples from the leftovers.

This is extremely memory-intensive because this set is recomputed and reallocated for every step of the algorithm. Instead of doing that, we can **precompute** and **preallocate** those sets:

`new_tier_lookup = [deleteat!(Vector(1:numtier), i) for i in 1:numtier]`

Testing indicated that generating the sets with a vector is faster than doing so with a set.

Now, instead of recomputing the selection set for each iteration, we can precompute them before running the algorithm using the above line of code, which generates a lookup table specifying all possible "new tiers" for a given "old tier". 

For example, if the original tier was 1, and there are 4 tiers total, our lookup table for 1 will return [2, 3, 4] as candidates.

If the original tier was 3, our lookup table will return [1, 2, 4] as candidates.

Then to randomly sample during the algorithm, we simply index the table:

`@inbounds new_tier = rand(new_tier_lookup[old_tier])`

which saves enough memory and improves enough on speed to induce a 2.5x speedup in the 5 tier case.
