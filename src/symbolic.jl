immutable SymbolicModel{ID,kind} <: ASM{ID,kind}
    symbols::OrderedDict{Symbol,Vector{Symbol}}
    equations::OrderedDict{Symbol,Vector{Expr}}
    calibration::OrderedDict{Symbol,Union{Expr,Symbol,Number}}
    options::Dict{Symbol,Any}
    definitions::OrderedDict{Symbol,Expr}
    model_type::Symbol
    name::UTF8String
    filename::UTF8String

    function SymbolicModel(recipe::Associative, symbols::Associative,
                           eqs::Associative, calib::Associative,
                           options::Associative, defs::Associative,
                           name="modeldoesnotwork", filename="none")
        # prep symbols
        model_type = symbol(recipe[:model_spec])
        _symbols = OrderedDict{Symbol,Vector{Symbol}}()
        for _ in recipe[:symbols]
            k = Symbol(_)
            _symbols[k] = Symbol[Symbol(v) for v in get(symbols, k, [])]
        end

        # prep equations: parse to Expr
        _eqs = OrderedDict{Symbol,Vector{Expr}}()
        for k in keys(recipe[:specs])

            # we handle these separately
            (k in [:arbitrage,]) && continue

            these_eq = get(eqs, k, [])

            # verify that we have at least 1 equation if section is required
            if !get(recipe[:specs][k], :optional, false)
                length(these_eq) == 0 && error("equation section $k required")
            end

            # finally pass in the expressions
            _eqs[k] = Expr[_to_expr(eq) for eq in these_eq]
        end

        # handle the arbitrage, arbitrage_exp, controls_lb, and controls_ub
        if haskey(recipe[:specs], :arbitrage)
            c_lb, c_ub, arb = _handle_arbitrage(eqs[:arbitrage],
                                                _symbols[:controls])
            _eqs[:arbitrage] = arb
            _eqs[:controls_lb] = c_lb
            _eqs[:controls_ub] = c_ub
        end

        # TODO: fixme. For now this throws or inserts a stub
        haskey(eqs, :arbitrage_exp) && error("Don't know how to do this yet")
        _eqs[:arbitrage_exp] = Expr[]

        # parse defs so values are Expr
        _defs = OrderedDict{Symbol,Expr}([k=>_to_expr(v) for (k, v) in defs])

        # prep calib: parse to Expr, Symbol, or Number
        _calib  = OrderedDict{Symbol,Union{Expr,Symbol,Number}}()
        for k in keys(_symbols)
            for nm in _symbols[k]
                if k == :shocks
                    _calib[nm] = 0.0
                else
                    _calib[nm] = _expr_or_number(calib[nm])
                end
            end
        end

        # add calibration for definitions
        for k in keys(_defs)
            _calib[k] = _expr_or_number(calib[k])
        end

        new(_symbols, _eqs, _calib, options, _defs, model_type, name, filename)
    end
end

function Base.show(io::IO, sm::SymbolicModel)
    println(io, """SymbolicModel
    - name: $(sm.name)
    """)
end

function SymbolicModel(data::Dict, model_type::Symbol, filename="none")
    # verify that we have all the required fields
    for k in ("symbols", "equations", "calibration")
        if !haskey(data, k)
            error("Yaml file must define section $k for DTCSCC model")
        end
    end

    d = _symbol_dict(deepcopy(data))
    if haskey(d, :model_type)
        model_type_data = pop!(d, :model_type)
        if string(model_type_data) != string(model_type)
            error(string("Supplied model type $(model_type) does not match ",
                         "model_type from data $(model_type_data)"))
        end
    end
    recipe = RECIPES[model_type]
    nm = pop!(d, :name, "modeldoesnotwork")
    id = gensym(nm)
    options = _symbol_dict(pop!(d, :options, Dict()))
    defs = _symbol_dict(pop!(d, :definitions, Dict()))
    out = SymbolicModel{id,model_type}(recipe, pop!(d, :symbols),
                                       pop!(d, :equations),
                                       pop!(d, :calibration),
                                       options,
                                       defs,
                                       nm,
                                       filename)

    if !isempty(d)
        m = string("Fields $(join(keys(d), ", ", ", and ")) from yaml file ",
                   " were not used when constructing SymbolicModel")
        warn(m)
    end
    out
end
