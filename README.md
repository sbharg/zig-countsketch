# zig-countsketch
Simple CountSketch and CountMinSketch implementations to help me learn Zig. 

CountSketch is a low-memory probabilistic data structure for processing a data stream in a single pass. At its core, it implicitly maintains a sparse, random linear projection that transforms a vector of dimension $n$ to a vector of dimension $w$, where $w \ll n$. It can be used to $(1 \pm \varepsilon)$-estimate the $L_2$ norm of the underlying frequency vector at the end of a data stream, and by maintaining multiple CountSketches in parallel, one can get reasonably accurate estimates of the frequency of each item in the data stream. CountMinSketch is a simpler data structure similar to CountSketch for estimating frequencies, but its theoretical guarantees only hold if the actual underlying frequencies of items are guaranteed to always be non-negative. 

This library implements a base `CountSketchBase` data structure, which is used to implement a `L2Estimator` data structure to estimate $L_2$ norms and a `CountSketch` data structure to approximate item frequencies. It also implements a `CountMinSketchBase` data structure, which is used to implement the full `CountMinSketch` data structure for estimate frequencies. 

There is also a `KWiseHash` type that both `CountSketchBase` and `CountMinSketchBase` use, which implements Carter-Wegman hashing to give a $k$-wise independent hash function. 

As of now, the implementations only works with keys that are at most u32 integers and frequencies that are signed integers.

## References

- Moses Charikar, Kevin Chen, and Martin Farach-Colton. Finding frequent items in data streams. *Theoretical Computer Science*, 312(1):3–15, 2004. [doi:10.1016/S0304-3975(03)00400-6](https://www.doi.org/10.1016/S0304-3975(03)00400-6).

- Kasper Green Larsen, Rasmus Pagh, Jakub Tětek. Countsketches, feature hashing and the median of three. In *Proc. of the 38th International Conference on Machine Learning (ICML 2021)*, pages 6011-6020, 2021. [url](https://proceedings.mlr.press/v139/larsen21a.html).

- Mikkel Thorup and Yin Zhang. Tabulation-based 5-independent hashing with applications to linear probing and second moment estimation. *SIAM Journal on Computing*, 41(2):293–331, 2012. [doi:10.1137/100800774](https://www.doi.org/10.1137/100800774).

- Graham Cormode and Shan Muthukrishnan. An improved data stream summary: the count-min sketch and its applications. *Journal of Algorithms*, 55(1):58-75, 2005. [doi:10.1016/j.jalgor.2003.12.001](https://www.doi.org/10.1016/j.jalgor.2003.12.001).