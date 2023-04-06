############################################################################################
# Errors and warnings
############################################################################################

"""
Error thrown when when a subproblem generates a column with negative (resp. positive) 
reduced cost in min (resp. max) problem that already exists in the master 
and that is already active. 
An active master column cannot have a negative reduced cost.
"""
struct ColumnAlreadyInsertedColGenWarning
    column_in_master::Bool
    column_is_active::Bool
    column_reduced_cost::Float64
    column_id::VarId
    master::Formulation{DwMaster}
    subproblem::Formulation{DwSp}
end

function Base.show(io::IO, err::ColumnAlreadyInsertedColGenWarning)
    msg = """
    Unexpected variable state during column insertion.
    ======
    Column id: $(err.column_id).
    Reduced cost of the column: $(err.column_reduced_cost).
    The column is in the master ? $(err.column_in_master).
    The column is active ? $(err.column_is_active).
    ======
    If the column is in the master and active, it means a subproblem found a solution with
    negative (minimization) / positive (maximization) reduced cost that is already active in
    the master. This should not happen.
    ======
    If you are using a pricing callback, make sure there is no bug in your code.
    If you are using a solver (e.g. GLPK, Gurobi...), check the reduced cost tolerance 
    `redcost_tol` parameter of `ColumnGeneration`.
    If you find a bug in Coluna, please open an issue at https://github.com/atoptima/Coluna.jl/issues with an example
    that reproduces the bug.
    ======
    """
    println(io, msg)
end

############################################################################################
# Information extracted to speed-up some computations.
############################################################################################
function _submatrix(
    form::Formulation, 
    keep_constr::Function, 
    keep_var::Function,
)
    matrix = getcoefmatrix(form)
    constr_ids = ConstrId[]
    var_ids = VarId[]
    nz = Float64[]
    for constr_id in Iterators.filter(keep_constr, Iterators.keys(getconstrs(form)))
        for (var_id, coeff) in @view matrix[constr_id, :]
            if keep_var(var_id)
                push!(constr_ids, constr_id)
                push!(var_ids, var_id)
                push!(nz, coeff)
            end
        end
    end
    return dynamicsparse(
        constr_ids, var_ids, nz, ConstrId(Coluna.MAX_NB_ELEMS), VarId(Coluna.MAX_NB_ELEMS)
    )
end

"""
Extracted information to speed-up calculation of reduced costs of subproblem representatives
and pure master variables.
We extract from the master the information we need to compute the reduced cost of DW 
subproblem variables:
- `dw_subprob_c` contains the perenial cost of DW subproblem representative variables
- `dw_subprob_A` is a submatrix of the master coefficient matrix that involves only DW subproblem
  representative variables.
We also extract from the master the information we need to compute the reduced cost of pure
master variables:
- `pure_master_c` contains the perenial cost of pure master variables
- `pure_master_A` is a submatrix of the master coefficient matrix that involves only pure master
  variables.

Calculation is `c - transpose(A) * master_lp_dual_solution`.

This information is given to the generic implementation of the column generation algorithm
through methods:
- ColGen.get_subprob_var_orig_costs 
- ColGen.get_orig_coefmatrix
"""
struct ReducedCostsCalculationHelper
    dw_subprob_c::SparseVector{Float64,VarId}
    dw_subprob_A::DynamicSparseMatrix{ConstrId,VarId,Float64}
    master_c::SparseVector{Float64,VarId}
    master_A::DynamicSparseMatrix{ConstrId,VarId,Float64}
end

"""
Function `var_duty_func(var_id)` returns `true` if we want to keep the variable `var_id`; `false` otherwise.
Same for `constr_duty_func(constr_id)`.
"""
function _get_costs_and_coeffs(master, var_duty_func, constr_duty_func)
    var_ids = VarId[]
    peren_costs = Float64[]

    for var_id in Iterators.keys(getvars(master))
        if iscuractive(master, var_id) && var_duty_func(var_id)
            push!(var_ids, var_id)
            push!(peren_costs, getcurcost(master, var_id))
        end
    end

    costs = sparsevec(var_ids, peren_costs, Coluna.MAX_NB_ELEMS)
    coef_matrix = _submatrix(master, constr_duty_func, var_duty_func)
    return costs, coef_matrix 
end

function ReducedCostsCalculationHelper(master)
    dw_subprob_c, dw_subprob_A = _get_costs_and_coeffs(
        master, 
        var_id -> getduty(var_id) <= AbstractMasterRepDwSpVar,
        constr_id -> !(getduty(constr_id) <= MasterConvexityConstr)
    )

    master_c, master_A = _get_costs_and_coeffs(
        master, 
        var_id -> getduty(var_id) <= AbstractOriginMasterVar,
        constr_id -> !(getduty(constr_id) <= MasterConvexityConstr)
    )

    return ReducedCostsCalculationHelper(dw_subprob_c, dw_subprob_A, master_c, master_A)
end

"""
Precompute information to speed-up calculation of subgradient of master variables.
We extract from the master follwowing information:
- `a` contains the perenial rhs of all master constraints except convexity constraints;
- `A` is a submatrix of the master coefficient matrix that involves only representative of
  original variables (pure master vars + DW subproblem represtative vars) 

Calculation is `a - A * (m .* z)`
where :
 - `m` contains a multiplicity factor for each variable involved in the calculation
       (lower or upper sp multiplicity depending on variable reduced cost);
 - `z` is the concatenation of the solution to the master (for pure master vars) and pricing
       subproblems (for DW subproblem represtative vars).

Operation `m .* z` "mimics" a solution in the original space.
"""
struct SubgradientCalculationHelper
    a::SparseVector{Float64,ConstrId}
    A::DynamicSparseMatrix{ConstrId,VarId,Float64}
end

function SubgradientCalculationHelper(master)
    constr_ids = ConstrId[]
    constr_rhs = Float64[]
    for (constr_id, constr) in getconstrs(master)
        if !(getduty(constr_id) <= MasterConvexityConstr) && 
           iscuractive(master, constr) && isexplicit(master, constr)
            push!(constr_ids, constr_id)
            push!(constr_rhs, getcurrhs(master, constr_id))
        end 
    end
    a = sparsevec(constr_ids, constr_rhs, Coluna.MAX_NB_ELEMS)
    A = _submatrix(
        master, 
        constr_id -> <condition to keep constr_id>,
        var_id -> Coluna.MathProg.getduty(var_id) <= MasterCol
    )
    return SubgradientCalculationHelper(a, A)
end