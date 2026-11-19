import math
results = [("ln(1.5)", 1660, math.log(1.5)), ("exp(1)", 11134, math.exp(1))]
print("function | Q12 | actual | reference | absolute error | relative error")
for name, q12, exact in results:
    actual = q12 / 4096
    err = abs(actual - exact)
    print(f"{name} | {q12} | {actual:.9f} | {exact:.9f} | {err:.9f} | {err/exact*100:.6f}%")
