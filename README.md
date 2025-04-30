# zig-countsketch
A simple CountSketch implementation to help me learn Zig. 

CountSketch is a low-memory probabilistic data structure for processing a data stream in a single pass. At its core, it implicitly maintains a sparse, random linear projection that transforms a vector of dimension $n$ to a vector of dimension $w$, where $w \ll n$. It can be used to $(1 \pm \varepsilon)$-estimate the $L_2$ norm of the underlying frequency vector at the end of a data stream, and by maintaining multiple CountSketches in parallel, one can get reasonably accurate estimates of the frequency of each item in the data stream. 

This library implements a base `CountSketchBase` data structure, which is used to implement a `L2Estimator` data structure to estimate $L_2$ norms and a `CountSketch` data structure to approximate item frequencies. It also includes a `KWiseHash` data structure, which implements Carter-Wegman hashing to give a $k$-wise independent hash function, which is used in `CountSketchBase`. 

As of now, the implementation only works with keys that are unsigned integers in the range [0, 2^61-1) and frequencies that are signed integers.

## References

- Moses Charikar, Kevin Chen, and Martin Farach-Colton. Finding frequent items in data streams. *Theoretical Computer Science*, 312(1):3–15, 2004. [doi:10.1016/S0304-3975(03)00400-6](https://www.doi.org/10.1016/S0304-3975(03)00400-6).

- Kasper Green Larsen, Rasmus Pagh, Jakub Tětek. Countsketches, feature hashing and the median of three. In *Proc. of the 38th International Conference on Machine Learning (ICML 2021)*, pages 6011-6020, 2021. [url](https://proceedings.mlr.press/v139/larsen21a.html).

- Mikkel Thorup and Yin Zhang. Tabulation-based 5-independent hashing with applications to linear probing and second moment estimation. *SIAM Journal on Computing*, 41(2):293–331, 2012. [doi:10.1137/100800774](https://www.doi.org/10.1137/100800774).