# Pose2 functions for Robot Motion Estimate

struct Pose2 <: IncrementalInference.InferenceVariable
  dims::Int
  labels::Vector{String}
  Pose2() = new(3, String["POSE";])
end

# TODO - move to IncrementalInference
struct Prior{T} <: IncrementalInference.FunctorSingleton where {T <: Distribution}
  z::T
end
getSample(s::Prior, N::Int=1) = (rand(s.z,N), )


mutable struct Pose2Pose2_NEW{T} <: IncrementalInference.FunctorPairwise where {T <: Distribution}
  z::T
  Pose2Pose2_NEW() where {T <: Distribution} = new{T}()
  Pose2Pose2_NEW(z1::T) where {T <: Distribution} = new{T}(z1)
  Pose2Pose2_NEW(mean::Vector{Float64}, cov::Array{Float64,2}) where {T <: Distribution} = new{Distributions.MvNormal}(MvNormal(mean, cov))
end
getSample(s::Pose2Pose2_NEW, N::Int=1) = (rand(s.z,N), )
function (s::Pose2Pose2_NEW)(res::Array{Float64},
      idx::Int,
      meas::Tuple,
      wxi::Array{Float64,2},
      wxj::Array{Float64,2}  )
  # res[1] = meas[1][idx] - (X2[1,idx] - X1[1,idx])
  wXjhat = SE2(wxi[:,idx])*SE2(meas[1][:,idx]) #*SE2(pp2.Zij[:,1])*SE2(meas[1][:,idx])
  jXjhat = SE2(wxj[:,idx]) \ wXjhat
  se2vee!(res, jXjhat)
  nothing
end



mutable struct PriorPose2 <: IncrementalInference.FunctorSingleton
    Zi::Array{Float64,2}
    Cov::Array{Float64,2}
    W::Array{Float64,1}
    PriorPose2() = new()
    PriorPose2(x...) = new(x[1], x[2], x[3])
end
function getSample(p2::PriorPose2, N::Int=1)
  return (rand(MvNormal(p2.Zi[:,1],p2.Cov),N), )
end


mutable struct Pose2Pose2 <: RoME.BetweenPoses # IncrementalInference.FunctorPairwise
    Zij::Array{Float64,2} # 2translations, 1rotation
    Cov::Array{Float64,2}
    W::Array{Float64,1}
    Pose2Pose2() = new()
    Pose2Pose2(x...) = new(x[1], x[2], x[3])
end
function getSample(pp2::Pose2Pose2, N::Int=1)
  return (rand(MvNormal(pp2.Zij[:,1],pp2.Cov),N), )
end
function (pp2::Pose2Pose2)(res::Array{Float64},
      idx::Int,
      meas::Tuple{Array{Float64,2}},
      wxi::Array{Float64,2},
      wxj::Array{Float64,2}  )
  #

  # TODO -- extend to allow multiple measurements also
  wXjhat = SE2(wxi[:,idx])*SE2(meas[1][:,idx]) #*SE2(pp2.Zij[:,1])*SE2(meas[1][:,idx])
  jXjhat = SE2(wxj[:,idx]) \ wXjhat
  se2vee!(res, jXjhat)
  nothing
end


function compare(a::PriorPose2,b::PriorPose2; tol::Float64=1e-10)
  TP = true
  TP = TP && norm(a.Zi-b.Zi) < tol
  TP = TP && norm(a.Cov-b.Cov) < tol
  TP = TP && norm(a.W-b.W) < tol
  return TP
end
function compare(a::Pose2Pose2,b::Pose2Pose2; tol::Float64=1e-10)
  TP = true
  TP = TP && norm(a.Zij-b.Zij) < tol
  TP = TP && norm(a.Cov-b.Cov) < tol
  TP = TP && norm(a.W-b.W) < tol
  return TP
end






# Project all particles (columns) Xval with Z, that is for all  SE3(Xval[:,i])*Z
function projectParticles(Xval::Array{Float64,2}, Z::Array{Float64,2}, Cov::Array{Float64,2})
  # TODO optimize convert SE2 to a type

  r,c = size(Xval)
  RES = zeros(r,c) #*cz

  # ent, x = SE3(0), SE3(0)
  j=1
  # for j in 1:cz
  ENT = rand( MvNormal(Z[:,1], Cov), c )
    for i in 1:c
      x = SE2(Xval[1:3,i])
      dx = SE2(ENT[1:3,i])
      RES[1:r,i*j] = se2vee(x*dx)
    end
  # end
  #
  return RES
end

⊕(Xpts::Array{Float64,2}, z::Pose2Pose2) = projectParticles(Xpts, z.Zij, z.Cov)
⊕(Xvert::Graphs.ExVertex, z::Pose2Pose2) = ⊕(getVal(Xvert), z)






# NOTE, for database support -- will be reduced to macro in future
# ------------------------------------


mutable struct PackedPriorPose2  <: IncrementalInference.PackedInferenceType
    vecZij::Array{Float64,1} # 0rotations, 1translation in each column
    dimz::Int
    vecCov::Array{Float64,1}
    dimc::Int
    W::Array{Float64,1}
    PackedPriorPose2() = new()
    PackedPriorPose2(x...) = new(x[1], x[2], x[3], x[4], x[5])
end
function convert(::Type{PriorPose2}, d::PackedPriorPose2)
  Zi = reshapeVec2Mat(d.vecZij,d.dimz)
  Cov = reshapeVec2Mat(d.vecCov, d.dimc)
  return PriorPose2(Zi, Cov, d.W)
end
function convert(::Type{PackedPriorPose2}, d::PriorPose2)
  v1 = d.Zi[:];
  v2 = d.Cov[:];
  return PackedPriorPose2(v1,size(d.Zi,1),
                          v2,size(d.Cov,1),
                          d.W)
end



# --------------------------------------------


mutable struct PackedPose2Pose2  <: IncrementalInference.PackedInferenceType
  vecZij::Array{Float64,1} # 2translations, 1rotation
  dimz::Int
  vecCov::Array{Float64,1}
  dimc::Int
  W::Array{Float64,1}
  PackedPose2Pose2() = new()
  PackedPose2Pose2(x...) = new(x[1], x[2], x[3], x[4], x[5])
end
function convert(::Type{Pose2Pose2}, d::PackedPose2Pose2)
  return Pose2Pose2(reshapeVec2Mat(d.vecZij,d.dimz),
                    reshapeVec2Mat(d.vecCov, d.dimc), d.W)
end
function convert(::Type{PackedPose2Pose2}, d::Pose2Pose2)
  v1 = d.Zij[:];
  v2 = d.Cov[:];
  return PackedPose2Pose2(v1,size(d.Zij,1),
                          v2,size(d.Cov,1),
                          d.W)
end





# --------------------------------------------



# old code below

# This has been moved to transform utils
# TODO Switch to using SE(2) oplus
# DX = [transx, transy, theta]
function addPose2Pose2!(retval::Array{Float64,1}, x::Array{Float64,1}, dx::Array{Float64,1})
  X = SE2(x)
  DX = SE2(dx)
  se2vee!(retval, X*DX)
  nothing
end
function addPose2Pose2(x::Array{Float64,1}, dx::Array{Float64,1})
    retval = zeros(3)
    addPose2Pose2!(retval, x, dx)
    return retval
end


function evalPotential(obs::PriorPose2, Xi::Array{Graphs.ExVertex,1}; N::Int=200)
    cov = diag(obs.Cov)
    ret = zeros(3,N)
    warn("should not be running")
    for j in 1:N
      for i in 1:size(obs.Zi,1)
        ret[i,j] += obs.Zi[i,1] + (cov[i]*randn())
      end
    end
    return ret
end



function evalPotential(odom::Pose2Pose2, Xi::Array{Graphs.ExVertex,1}, Xid::Int; N::Int=100)
    rz,cz = size(odom.Zij)
    Xval = Array{Float64,2}()
    XvalNull = Array{Float64,2}()
    warn("should not be running")
    # implicit equation portion -- bi-directional pairwise function
    if Xid == Xi[1].index #odom.
        #Z = (odom.Zij\eye(rz)) # this will be used for group operations
        Z = se2vee(SE2(vec(odom.Zij)) \ eye(3))
        Xval = getVal(Xi[2])
        XvalNull = getVal(Xi[1])
    elseif Xid == Xi[2].index
        Z = odom.Zij
        Xval = getVal(Xi[1])
        XvalNull = getVal(Xi[2])
    else
        error("Bad evalPairwise Pose2Pose2")
    end

    r,c = size(Xval)
    RES = zeros(r,c*cz)

    # TODO -- this should be the covariate error from Distributions, only using diagonals here (approxmition for speed in first implementation)
    # dd = size(Z,1) == r
    ENT = randn(r,c)
    HYP = rand(Categorical(odom.W),c) # TODO consolidate
    HYP -= length(odom.W)>1 ? 1 : 0
    for d in 1:r
       @fastmath @inbounds ENT[d,:] = ENT[d,:].*odom.Cov[d,d]
    end
    # Repeat ENT values for new modes from meas
    for j in 1:cz
      for i in 1:c
        if HYP[i]==1 # TODO consolidate hypotheses on Categorical
          z = Z[1:r,j].+ENT[1:r,i]
          RES[1:r,i*j] = addPose2Pose2(Xval[1:r,i], z )
        else
          RES[1:r,i*j] = XvalNull[1:r,i]
        end
      end
    end

    return RES
end
