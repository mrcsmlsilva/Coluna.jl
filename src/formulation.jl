mutable struct Formulation{Duty <: AbstractFormDuty}  <: AbstractFormulation
    uid::FormId
    parent_formulation::Union{AbstractFormulation, Nothing} # master for sp, reformulation for master
    #moi_model::Union{MOI.ModelLike, Nothing}
    moi_optimizer::Union{MOI.AbstractOptimizer, Nothing}
    vars::Manager{Variable, VarInfo} 
    constrs::Manager{Constraint, ConstrInfo} 
    memberships::Memberships
    obj_sense::ObjSense
    callback
    primal_inc_bound::Float64
    dual_inc_bound::Float64
    primal_solution_record::Union{PrimalSolution, Nothing}
    dual_solution_record::Union{DualSolution, Nothing}
end

function Formulation(Duty::Type{<: AbstractFormDuty},
                     m::AbstractModel, 
                     parent_formulation::Union{AbstractFormulation, Nothing},
                     moi_optimizer::Union{MOI.AbstractOptimizer, Nothing})
    uid = getnewuid(m.form_counter)
    return Formulation{Duty}(uid,
                             parent_formulation,
                             #moi_model,
                             moi_optimizer, 
                             Manager{Variable, VarInfo}(),
                             Manager{Constraint, ConstrInfo}(),
                             Memberships(),
                             Min,
                             nothing,
                             Inf,
                             -Inf,
                             nothing,
                             nothing)
end

function Formulation(Duty::Type{<: AbstractFormDuty},
                     m::AbstractModel, 
                     optimizer::Union{MOI.AbstractOptimizer, Nothing})
    return Formulation(Duty, m, nothing, optimizer)
end

function Formulation(Duty::Type{<: AbstractFormDuty}, m::AbstractModel, 
                     parent_formulation::Union{AbstractFormulation, Nothing})
    return Formulation(Duty, m, parent_formulation, nothing)
end

function Formulation(Duty::Type{<: AbstractFormDuty}, m::AbstractModel)
    return Formulation(Duty, m, nothing, nothing)
end

#getvarcost(f::Formulation, uid) = f.costs[uid]
#getvarlb(f::Formulation, uid) = f.lower_bounds[uid]
#getvarub(f::Formulation, uid) = f.upper_bounds[uid]
#getvartype(f::Formulation, uid) = f.var_types[uid]

#getconstrrhs(f::Formulation, uid) = f.rhs[uid]
#getconstrsense(f::Formulation, uid) = f.constr_senses[uid]


#activevar(f::Formulation) = f.vars.members[activemask(f.vars.status)]
#staticvar(f::Formulation) = f.vars.members[staticmask(f.vars.status)]
#dynamicvar(f::Formulation) = f.vars.members[dynamicmask(f.vars.status)]
#artificalvar(f::Formulation) = f.vars.members[artificialmask(f.vars.status)]
#activeconstr(f::Formulation) = f.constrs.members[activemask(f.constrs.status)]
#staticconstr(f::Formulation) = f.constrs.members[staticmask(f.constrs.status)]
#dynamicconstr(f::Formulation) = f.constrs.members[dynamicmask(f.constrs.status)]


getuid(f::Formulation) = f.uid
getvar(f::Formulation, uid::VarId) = getvc(f.vars, uid)
getconstr(f::Formulation, uid::ConstrId) = getvc(f.constrs, uid)
get_var_uids(f::Formulation) = get_nz_ids(f.vars)
get_var_uids(f::Formulation, d::Type{<:AbstractVarDuty}) = getuids(f.vars, d)
get_var_uids(fo::Formulation, fu::Function) = getuids(fo.vars, fu)
get_var_uids(fo::Formulation, fi::Filter) = getuids(fo.vars, fi)
get_constr_uids(f::Formulation, d::Type{<:AbstractConstrDuty}) = getuids(f.constrs, d)
get_constr_uids(f::Formulation) = get_nz_ids(f.constrs)
getobjsense(f::Formulation) = f.obj_sense
        
get_constr_members_of_var(f::Formulation, uid) = get_constr_members_of_var(f.memberships, uid)
get_var_members_of_constr(f::Formulation, uid) = get_var_members_of_constr(f.memberships, uid)

get_constr_members_of_var(f::Formulation, var::Variable) = get_constr_members_of_var(f, getuid(var))
get_var_members_of_constr(f::Formulation, constr::Constraint) = get_var_members_of_constr(f, getuid(constr))

function clone_in_formulation!(varconstr::AbstractVarConstr,
                               src::Formulation,
                               dest::Formulation,
                               flag::Flag,
                               duty)
    varconstr_copy = copy(varconstr, flag, duty)
    setform!(varconstr_copy, getuid(dest))
    add!(dest, varconstr_copy)
    return varconstr_copy
end

function clone_in_formulation!(var_uids::Vector{VarId},
                               src_form::Formulation,
                               dest_form::Formulation,
                               flag::Flag,
                               duty::Type{<: AbstractVarDuty})
    for var_uid in var_uids
        var = getvar(src_form, var_uid)
        var_clone = clone_in_formulation!(var, src_form, dest_form, flag, duty)
        reset_constr_members_of_var!(dest_form.memberships, var_uid,
                                     get_constr_members_of_var(src_form, var_uid))
    end
    return 
end

function clone_in_formulation!(constr_uids::Vector{ConstrId},
                               src_form::Formulation,
                               dest_form::Formulation,
                               flag::Flag,
                               duty::Type{<: AbstractConstrDuty})
    for constr_uid in constr_uids
        constr = getconstr(src_form, constr_uid)
        constr_clone = clone_in_formulation!(constr, src_form, dest_form, flag, duty)
        set_var_members_of_constr!(dest_form.memberships, constr_uid,
                                     get_var_members_of_constr(src_form, constr_uid))
    end
    
    return 
end

#==function clone_in_formulation!(varconstr::AbstractVarConstr, src::Formulation, dest::Formulation, duty; membership = false)
    varconstr_copy = deepcopy(varconstr)
    setform!(varconstr_copy, getuid(dest))
    setduty!(varconstr_copy, duty)
    if membership
        m = get_constr_members(src, varconstr)
        m_copy = deepcopy(m)
        add!(dest, varconstr_copy, m_copy)
    else
        add!(dest, varconstr_copy)
    end
    return
end ==#

function add!(f::Formulation, elems::Vector{VarConstr}) where {VarConstr <: AbstractVarConstr}
    for elem in elems
        add!(f, elem)
    end
    return
end

function add!(f::Formulation, elems::Vector{VarConstr}, 
              memberships::Vector{M}) where {VarConstr <: AbstractVarConstr,
                                                  M <: AbstractMembership}
    @assert length(elems) == length(memberships)
    for i in 1:length(elems)
        add!(f, elems[i], memberships[i])
    end
    return
end

function add!(f::Formulation, var::Variable)
    add!(f.vars, var)
    add_variable!(f.memberships, getuid(var)) 
    return
end

function add!(f::Formulation, var::Variable, membership::ConstrMembership)
    add!(f.vars, var)
    add_variable!(f.memberships, getuid(var), membership)
    return
end

function add!(f::Formulation, constr::Constraint)
    add!(f.constrs, constr)
    f.constr_rhs[getuid(constr)] = constr.rhs
    add_constraint!(f.memberships, getuid(constr))
    return
end

function add!(f::Formulation, constr::Constraint, membership::VarMembership)
    add!(f.constrs, constr)
    f.constr_rhs[getuid(constr)] = constr.rhs
    add_constraint!(f.memberships, getuid(constr), membership)
    return
end

function register_objective_sense!(f::Formulation, min::Bool)
    # if !min
    #     m.obj_sense = Max
    #     m.costs *= -1.0
    # end
    !min && error("Coluna does not support maximization yet.")
    return
end

function optimize(form::Formulation, optimizer = form.moi_optimizer, update_form = true)    
    call_moi_optimize_with_silence(form.moi_optimizer)
    status = MOI.get(form.moi_optimizer, MOI.TerminationStatus())
    primal_sols = PrimalSolution[]
    @logmsg LogLevel(-4) string("Optimization finished with status: ", status)
    if MOI.get(optimizer, MOI.ResultCount()) >= 1
        primal_sol = retrieve_primal_sol(form)
        push!(primal_sols, primal_sol)
        dual_sol = retrieve_dual_sol(form)
        if update_form
            form.primal_solution_record = primal_sol
            if dual_sol != nothing
                dual_solution_record = dual_sol
            end
        end

        return (status, primal_sol.value, primal_sols, dual_sol)
    end
    @logmsg LogLevel(-4) string("Solver has no result to show.")
    return (status, +inf, nothing, nothing)
end

function compute_original_cost(sol::PrimalSolution, form::Formulation)
    cost = 0.0
    for (var_uid, val) in sol.members
        var = getvar(form,var_uid)
        cost += var.cost * val
    end
    @logmsg LogLevel(-4) string("intrinsic_cost = ",cost)
    return cost
end

function _show_obj_fun(io::IO, f::Formulation)
    print(io, getobjsense(f), " ")
    for uid in get_var_uids(f)
        var = getvar(f, uid)
        name = getname(var)
        cost = getcost(var)
        op = (cost < 0.0) ? "-" : "+" 
        #if cost != 0.0
            print(io, op, " ", abs(cost), " ", name, " ")
        #end
    end
    println(io, " ")
    return
end

function _show_constraint(io::IO, f::Formulation, uid)
    constr = getconstr(f, uid)
    print(io, " ", getname(constr), " : ")

    m = get_var_members_of_constr(f, constr)
    var_uids, var_coeffs = get_ids_vals(m)
    for i in 1:length(var_uids)
        var = getvar(f, var_uids[i])
        name = getname(var)
        coeff = var_coeffs[i]
        op = (coeff < 0.0) ? "-" : "+"
        print(io, op, " ", abs(coeff), " ", name, " ")
    end

    if getsense(constr) == Equal
        op = "=="
    elseif getsense(constr) == Greater
        op = ">="
    else
        op = "<="
    end
    print(io, " ", op, " ", getrhs(constr))
    d = getduty(constr)
    println(io, " (", d ,")")
    return
end

function _show_constraints(io::IO , f::Formulation)
    for uid in get_constr_uids(f)
        _show_constraint(io, f, uid)
    end
    return
end

function _show_variable(io::IO, f::Formulation, uid)
    var = getvar(f, uid)
    name = getname(var)
    lb = getlb(var)
    ub = getub(var)
    t = gettype(var)
    d = getduty(var)
    f = getflag(var)
    println(io, lb, " <= ", name, " <= ", ub, " (", t, " | ", d ," | ", f , ")")
end

function _show_variables(io::IO, f::Formulation)
    for uid in get_var_uids(f)
        _show_variable(io, f, uid)
    end
end

function Base.show(io::IO, f::Formulation)
    println(io, "Formulation id = ", getuid(f))
    _show_obj_fun(io, f)
    _show_constraints(io, f)
    _show_variables(io, f)
    return
end
