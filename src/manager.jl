# Define default functions to use as filters
# Functions must be of the form:
# f(::Pair{<:AbstractVarConstrId,
#          <:Pair{<:AbstractVarConstr, <:AbstractVarConstrInfo}})::Bool

struct Manager{Id <: AbstractVarConstrId, T}  <: AbstractManager
    members::Dict{Id,T}
end

getmembers(m::Manager) = m.members

has(m::Manager, id::AbstractVarConstrId) = haskey(m.members, id)

get(m::Manager, id::AbstractVarConstrId) = m.members[id]

get(m::Manager, uid::Int) = m.members[Id(uid)]

getids(m::Manager) = collect(keys(m.members))

iterate(m::Manager) = iterate(m.members)

iterate(m::Manager, state) = iterate(m.members, state)

length(m::Manager) = length(m.members)

getindex(m::Manager, elements) = getindex(m.members, elements)

lastindex(m::Manager) = lastindex(m.members)

Base.filter(f::Function, m::Manager) = filter(f, m.members)

clone(m::Manager{T,U}) where {T,U} = Membership{T,U}(copy(m.members))

function set!(m::Manager{Id,T}, id::Id, val::T) where {Id, T}
    m.members[id] = val
    return
end

function Base.show(io::IO, m::Manager)
    println(io, typeof(m), ":")
    for e in m.members
        println(io, "  ", e)
    end
    return
end

Manager(vc_type::Type{<:AbstractVarConstr},
        val_type::DataType) =
            Manager{idtype(vc_type), val_type}(Dict{idtype(vc_type),val_type}())


# Maybe we should do something like:
# const VcManager{T} = Manager{T,T}

VcManager(T::Type{<:AbstractVarConstr}) = Manager(T, T)


getvarconstr(e::Pair{Id,VC}) where {Id, VC} = e[2]
