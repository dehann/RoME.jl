# Point2D mutable struct

struct Point2 <: IncrementalInference.InferenceVariable
  dims::Int
  labels::Vector{String}
  Point2() = new(2, String["";])
end

mutable struct PriorPoint2D <: IncrementalInference.FunctorSingleton
  mv::MvNormal
  W::Array{Float64,1}
  PriorPoint2D() = new()
  PriorPoint2D(mu, cov, W) = new(MvNormal(mu, cov), W)
end
function getSample(p2::PriorPoint2D, N::Int=1)
  return (rand(p2.mv, N),)
end

mutable struct Point2DPoint2DRange <: IncrementalInference.FunctorPairwiseMinimize #Pairwise
    Zij::Vector{Float64} # bearing and range hypotheses as columns
    Cov::Float64
    W::Vector{Float64}
    Point2DPoint2DRange() = new()
    Point2DPoint2DRange(x...) = new(x[1],x[2],x[3])
end
function (pp2r::Point2DPoint2DRange)(
      res::Array{Float64},
      idx::Int,
      meas::Tuple, # Array{Float64,2},
      xi::Array{Float64,2},
      lm::Array{Float64,2} )
  #
  # TODO -- still need to add multi-hypotheses support here
  # this is the noisy range
  z = pp2r.Zij[1]+meas[1][1,idx]
  # theta = meas[2]
  XX = lm[1,idx] - (z*cos(meas[2][idx]) + xi[1,idx])
  YY = lm[2,idx] - (z*sin(meas[2][idx]) + xi[2,idx])
  res[1] = XX^2 + YY^2
  # nothing
end
function getSample(pp2::Point2DPoint2DRange, N::Int=1)
  return (pp2.Cov*randn(1,N),  2*pi*rand(N))
end



mutable struct Point2DPoint2D <: BetweenPoses
    Zij::Distribution
    Point2DPoint2D() = new()
    Point2DPoint2D(x) = new(x)
end
function (pp2r::Point2DPoint2D)(
      res::Array{Float64},
      idx::Int,
      meas::Tuple, # Array{Float64,2},
      xi::Array{Float64,2},
      xj::Array{Float64,2} )
  #
  # TODO -- still need to add multi-hypotheses support here
  res[1]  = meas[1][1,idx] - (xj[1,idx] - xi[1,idx])
  res[2]  = meas[1][2,idx] - (xj[2,idx] - xi[2,idx])
  nothing
end
function getSample(pp2::Point2DPoint2D, N::Int=1)
  return (rand(pp2.Zij,N),  )
end





mutable struct PriorPoint2DensityNH <: IncrementalInference.FunctorSingletonNH
  belief::BallTreeDensity
  nullhypothesis::Distributions.Categorical
  PriorPoint2DensityNH() = new()
  PriorPoint2DensityNH(belief, p) = new(belief, Distributions.Categorical(p))
end
function getSample(p2::PriorPoint2DensityNH, N::Int=1)
  return (rand(p2.belief, N), )
end
mutable struct PackedPriorPoint2DensityNH <: IncrementalInference.PackedInferenceType
    rpts::Vector{Float64} # 0rotations, 1translation in each column
    rbw::Vector{Float64}
    dims::Int
    nh::Vector{Float64}
    PackedPriorPoint2DensityNH() = new()
    PackedPriorPoint2DensityNH(x1,x2,x3, x4) = new(x1, x2, x3, x4)
end
function convert(::Type{PriorPoint2DensityNH}, d::PackedPriorPoint2DensityNH)
  return PriorPoint2DensityNH(
            kde!(EasyMessage( reshapeVec2Mat(d.rpts, d.dims), d.rbw)),
            Distributions.Categorical(d.nh)  )
end
function convert(::Type{PackedPriorPoint2DensityNH}, d::PriorPoint2DensityNH)
  return PackedPriorPoint2DensityNH( getPoints(d.belief)[:], getBW(d.belief)[:,1], Ndim(d.belief), d.nullhypothesis.p )
end



# Old evalPotential functions
function evalPotential(prior::PriorPoint2D, Xi::Array{Graphs.ExVertex,1}; N::Int=100)#, from::Int)
    return rand(prior.mv, N)
end

# Solve for Xid, given values from vertices [Xi] and measurement rho
function evalPotential(rho::Point2DPoint2DRange, Xi::Array{Graphs.ExVertex,1}, Xid::Int)
  fromX, ret = nothing, nothing
  if Xi[1].index == Xid
    fromX = getVal( Xi[2] )
    ret = deepcopy(getVal( Xi[1] )) # carry pose yaw row over if required
  elseif Xi[2].index == Xid
    fromX = getVal( Xi[1] )
    ret = deepcopy(getVal( Xi[2] )) # carry pose yaw row over if required
  end
  r,c = size(fromX)
  theta = 2*pi*rand(c)
  noisy = rho.Cov*randn(c) + rho.Zij[1]

  for i in 1:c
    ret[1,i] = noisy[i]*cos(theta[i]) + fromX[1,i]
    ret[2,i] = noisy[i]*sin(theta[i]) + fromX[2,i]
  end
  return ret
end






















# ---------------------------------------------------------



mutable struct PackedPriorPoint2D  <: IncrementalInference.PackedInferenceType
    mu::Array{Float64,1}
    vecCov::Array{Float64,1}
    dimc::Int
    W::Array{Float64,1}
    PackedPriorPoint2D() = new()
    PackedPriorPoint2D(x...) = new(x[1], x[2], x[3], x[4])
end

passTypeThrough(d::FunctionNodeData{Point2DPoint2DRange}) = d

function convert(::Type{PriorPoint2D}, d::PackedPriorPoint2D)
  Cov = reshapeVec2Mat(d.vecCov, d.dimc)
  return PriorPoint2D(d.mu, Cov, d.W)
end
function convert(::Type{PackedPriorPoint2D}, d::PriorPoint2D)
  v2 = d.mv.Σ.mat[:];
  return PackedPriorPoint2D(d.mv.μ, v2, size(d.mv.Σ.mat,1), d.W)
end

# no longer needed -- using multiple dispatch
# function convert(::Type{PackedFunctionNodeData{PackedPriorPoint2D}}, d::FunctionNodeData{PriorPoint2D})
#   return PackedFunctionNodeData{PackedPriorPoint2D}(d.fncargvID, d.eliminated, d.potentialused, d.edgeIDs,
#           string(d.frommodule), convert(PackedPriorPoint2D, d.fnc))
# end
# function convert(::Type{FunctionNodeData{PriorPoint2D}}, d::PackedFunctionNodeData{PackedPriorPoint2D})
#   return FunctionNodeData{PriorPoint2D}(d.fncargvID, d.eliminated, d.potentialused, d.edgeIDs,
#           Symbol(d.frommodule), convert(PriorPoint2D, d.fnc))
# end
# function FNDencode(d::FunctionNodeData{PriorPoint2D})
#   return convert(PackedFunctionNodeData{PackedPriorPoint2D}, d)
# end
# function FNDdecode(d::PackedFunctionNodeData{PackedPriorPoint2D})
#   return convert(FunctionNodeData{PriorPoint2D}, d)
# end



mutable struct PackedPoint2DPoint2DRange  <: IncrementalInference.PackedInferenceType
    Zij::Vector{Float64} # bearing and range hypotheses as columns
    Cov::Float64
    W::Vector{Float64}
    PackedPoint2DPoint2DRange() = new()
    PackedPoint2DPoint2DRange(x...) = new(x[1],x[2],x[3])
    PackedPoint2DPoint2DRange(x::Point2DPoint2DRange) = new(x.Zij,x.Cov,x.W)
end
function convert(::Type{PackedPoint2DPoint2DRange}, d::Point2DPoint2DRange)
  return PackedPoint2DPoint2DRange(d)
end
function convert(::Type{Point2DPoint2DRange}, d::PackedPoint2DPoint2DRange)
  return Point2DPoint2DRange(d.Zij, d.Cov, d.W)
end






mutable struct PackedPoint2DPoint2D <: IncrementalInference.PackedInferenceType
    mu::Vector{Float64}
    sigma::Vector{Float64}
    sdim::Int
    PackedPoint2DPoint2D() = new()
    PackedPoint2DPoint2D(x, y, d) = new(x,y,d)
end
function convert(::Type{Point2DPoint2D}, d::PackedPoint2DPoint2D)
  return Point2DPoint2D( MvNormal(d.mu, reshapeVec2Mat(d.sigma, d.sdim)) )
end
function convert(::Type{PackedPoint2DPoint2D}, d::Point2DPoint2D)
  return PackedPoint2DPoint2D( d.Zij.μ, d.Zij.Σ.mat[:], size(d.Zij.Σ.mat,1) )
end
