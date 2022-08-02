## Accelerated SBM Sampler

The accelerated sampler in `type_allocation.jl` combines several optimizations for the original SBM procedure. These can be grouped into three categories:

### Parallelization

On multi-threaded machines, additional processing power is available through the use of threading. Multiple computations can be conducted on parallel "threads" and compared at the end of a given search period. 

In our case, the SBM algorithm searches through the set of all departments in order to determine which type reallocations will produce improvements to the likelihood function. By default, the algorithm samples randomly from the full set of departments. Given that the machines the algorithm runs on support multithreading, multiple orders of magnitude of runtime improvements can be made by assigning different regions of the set of departments to different threads.

For example, instead of searching departments 1 through 462 on one thread, we can assign departments 1 to 231 and departments 232 to 462 to two separate search threads. These search threads will run at the same time instead of in sequence and be able to cover twice as much of the search space as the single-threaded algorithm can in the same amount of time.

Once a search thread finds an improvement, it then signals the program (i.e. the thread manager, which has its own thread) to update all search threads with this improvement, after which the search threads reset and start searching again.

As a side bonus, the termination procedure of waiting until 30,000 reallocations in sequence have produced no likelihood improvements can now be distributed over search threads, although this procedure was further optimized using the following change.

### Early-Stopping

There are two early-stopping improvements which allow the algorithm to spend less time on redundant calculations:

#### Seach Thread Termination

The first is an early-stopping procedure in the search threads. Given that the likelihood computation is now more efficient, it has become viable to conduct a thorough validation of the existence of further likelihood improvements after a certain period of search time.

After 500-1000 periods of no improvements on any of the search threads (which for e.g. 7 threads is actually 3500-7000 searches), it is often a good guess that the algorithm is either close to or exactly unable to make any further optimizations.

The early-stopping procedure, to implement this guess, attempts to reallocate, in sequence, every department to every possible tier. This is the full set of possible reallocations given the current allocation.

If none of these reallocations produce a likelihood improvement, then we know with certainty that no further improvements are possible, so we can stop the search threads without having to wait for 30,000 reallocations as before.

Currently this procedure is done redundantly on all search threads at once, as to distribute it would require extra code for data communication between the search threads. At the moment, distributing it is not necessary but can be added for additional speed benefits if required.

#### Likelihood Shortcutting

The likelihood function updates by sequentially adding the likelihood of each individual department-department pair. Our objective function declares an improvement only if the result of the procedure is less than the previous best objective value.

As the update is sequential, if at an intermediate point in time the accumulated likelihood is already greater than the objective function, then it will be impossible for it to be better than the previous result by the time it is finished computation. Thus, the function can end early and report no improvement.

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

$$log(\mathcal{\tilde \tilde L}(\lambda_{t_i, t_j, \forall i, j})) = \sum\limits_{i = 1}^{M}\sum\limits_{j = 1}^{N} \hat A_{i, j} log(\lambda_{t_i, t_j})$$

Finally, the algorithm itself keeps track of the numerator of $\lambda_{t_i, t_j}$ as a separate variable for efficiency purposes. Define:

$$T_{a,b} = \sum\limits_{i = 1, t_i = a}^{M}\sum\limits_{j = 1, t_j = b}^{N} \hat A_{i, j}$$

such that $\lambda_{a, b} = \frac{T_{a, b}}{M_a N_b}$. 

We can rewrite the double sum into partial sums as:

$$\sum\limits_{a = 1}^{K}\sum\limits_{b = 1}^{K+1}\sum\limits_{i = 1, t_i = a}^{M}\sum\limits_{j = 1, t_j = b}^{N} \hat A_{i, j} log(\lambda_{a, b})$$

Which then simplifies to the following given that $log(\lambda_{a, b})$ is independent of $i$ and $j$ and can thus move outside of the rightmost two sums:

$$log(\mathcal{\tilde \tilde \tilde L}(\lambda_{t_i, t_j, \forall i, j})) \sum\limits_{a = 1}^{K}\sum\limits_{b = 1}^{K+1} T_{a,b} log(\frac{T_{a,b}}{M_a N_b})$$

This is the setup in use in the current version of the algorithm.

