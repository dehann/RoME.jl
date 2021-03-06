using RoME, IncrementalInference, TransformUtils
using Base.Test


println("Increased dimension root finding test")

# 3 dimensional line, z = [a b][x y]' + c
function rotationresidual!(res::Vector{Float64}, z::Vector{Float64}, var::Tuple)
  q1 = convert(Quaternion, Euler(z...))
  q2 = convert(Quaternion, so3(var[2]))
  qq = q1*q_conj(q2)
  res[1:3] = vee(convert(so3, qq))
  nothing
end

for i in 1:10
  eul = 0.25*randn(3)
  # res = zeros(3)
  # @show rotationresidual!(res, eul, (zeros(0),x0))
  # @show res
  gg = (res, x) -> rotationresidual!(res, eul, (zeros(0),x))
  x0 = 0.1*randn(3)
  res = zeros(3)
  # @show gg(res, x0)
  # @show res
  y = numericRootGenericRandomizedFnc(
          gg,
          3, 3, x0   )
  # test the result
  @show q1 = convert(Quaternion, Euler(eul...))
  @show q2 = convert(Quaternion, so3(y))
  @test TransformUtils.compare(q1, q2, tol=1e-8)
end
