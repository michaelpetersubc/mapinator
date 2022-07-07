
INSTALL_PACKAGES = false   # change this to true if you are running this notebook for the first time
YEAR_INTERVAL = 2003:2021  # change this to select the years of data to include in the estimation
NUMBER_OF_TYPES = 4        # change this to select the number of types to classify academic departments into
NUMBER_OF_SINKS = 1        # change this to 4 to use individual sink types
SAVE_TO_DATABASE = false   # change to true to save the type allocation to the database
TOTAL_DISTRIBUTIONS = NUMBER_OF_TYPES + NUMBER_OF_SINKS


import Pkg
for package in ["BlackBoxOptim", "Distributions", "ForwardDiff", "JSON", "Optim", "Quadrature", 
        "StatsPlots","DotEnv","MySQL","DBInterface","Tables"]
    if INSTALL_PACKAGES
        Pkg.add(package)
    end
end
using  JSON, HTTP, Distributions, DotEnv, MySQL, DBInterface, Tables

function get_data(url)
    resp = HTTP.get(url);
    es = String(resp.body)
    return placements = JSON.parse(es)
end

function find_inst(name::String,outcomes,to_from::Bool = false)
    check = false
    for outcome in outcomes
        if to_from == true
            if outcome["to_name"] == name
                println(outcome)
                check = true
            end
        else
            if outcome["from_institution_name"] == name
                println(outcome)
                check = true
            end
        end
    end
    if check == false
        println("Not found")
    end
end

url = "https://support.econjobmarket.org/api/placement_data"
placements = get_data(url);
println(length(placements))
println(typeof(placements))

const DB = DBInterface
cfg = DotEnv.config()

i = 0
oid_mapping = Dict{}()
institution_mapping = Dict{}()
academic = Set{}()
academic_to = Set{}()
academic_builder = Set{}()
sink_builder = Set{}()
for placement in placements
    if in(parse(Int64, placement["year"]), YEAR_INTERVAL)
        push!(academic, placement["from_institution_name"])
        push!(academic_to, placement["to_name"])
        oid_mapping[placement["from_oid"]] = placement["from_institution_id"]
        oid_mapping[placement["to_oid"]] = placement["to_institution_id"]
        institution_mapping[placement["from_institution_id"]] = placement["from_institution_name"]
        institution_mapping[placement["to_institution_id"]] = placement["to_name"]
        if placement["position_name"] == "Assistant Professor"
            push!(academic_builder, placement)
        else
            push!(sink_builder, placement)
        end
    end
end

tch_sink = Set{}() # sink of teaching universities that do not graduate PhDs
for key in academic_to
    if !(key in academic)
        push!(tch_sink, key)
    end
end

acd_sink = Set{}()
gov_sink = Set{}()
pri_sink = Set{}()

for outcome in sink_builder
    # CODE global academic, other_placements, pri_sink, gov_sink, acd_sink
    if outcome["recruiter_type"] in ["6","7"]
        # private sector: for and not for profit
        push!(pri_sink, string(outcome["to_name"], " (private sector)"))
    elseif outcome["recruiter_type"] == "5"
        # government institution
        push!(gov_sink, string(outcome["to_name"], " (public sector)"))
    else
        # everything else including terminal academic positions
        push!(acd_sink, string(outcome["to_name"], " (academic sink)"))
    end
end

institutions = vcat(collect(academic), collect(acd_sink), collect(gov_sink), collect(pri_sink), collect(tch_sink))


out = zeros(Int64, length(institutions), length(collect(academic)))
i = 0
for outcome in academic_builder
    global i
    i += 1
    out[findfirst(isequal(outcome["to_name"]), institutions), findfirst(isequal(outcome["from_institution_name"]), institutions)] += 1
end
for outcome in sink_builder
    global i
    i += 1
    keycheck = ""
    if outcome["recruiter_type"] in ["6", "7"]
        keycheck = string(outcome["to_name"], " (private sector)")
    elseif outcome["recruiter_type"] == "5"
        keycheck = string(outcome["to_name"], " (public sector)")
    else
        keycheck = string(outcome["to_name"], " (academic sink)")
    end
    #println(keycheck)
    #println(findfirst(isequal(keycheck), institutions))
    #println(outcome["from_institution_name"]," ",findfirst(isequal(outcome["from_institution_name"]), institutions))
    out[findfirst(isequal(keycheck), institutions), findfirst(isequal(outcome["from_institution_name"]), institutions)] += 1
end

function bucket_estimate(assign::Array{Int8}, A::Matrix{Int64}, num, numsink,b)
    
    T = zeros(num + numsink, num)
    count = zeros(num + numsink, num)
    for i in 1:size(A)[1], j in 1:size(A)[2]
         @inbounds val = (num + 1) * (assign[j] - 1) + assign[i]
         @inbounds b[i, j] = val
         @inbounds T[val] = ((T[val] * count[val]) + A[i, j]) / (count[val] + 1)
         @inbounds count[val] += 1
    end
    L = 0.0
    @simd for i in eachindex(A)
        @inbounds L += logpdf(Poisson(T[b[i]]), A[i])
    end
    return -L, T
end


function doit(sample, academic_institutions, asink, gsink, psink, tsink, all_institutions, num, numsink)
    # some initial states
    b = zeros(Int64, size(sample)[1], size(sample)[2])
    current_allocation = Array{Int8}(undef, length(all_institutions))
    cur_objective = Inf
    best_mat = nothing
    cursor = 1
    for inst in academic_institutions
        current_allocation[cursor] = 1
        cursor += 1
    end
    # the sinks must stay in fixed types
    # this was built to support more sinks, but by default we only use one
    # change the "current_allocation[cursor] = ..." lines to group sinks together
    for key in asink # other academic
        current_allocation[cursor] = num + min(1, numsink)
        cursor += 1
    end
    for key in gsink # public sector
        current_allocation[cursor] = num + min(2, numsink)
        cursor += 1
    end
    for key in psink # private sector
        current_allocation[cursor] = num + min(3, numsink)
        cursor += 1
    end
    for key in tsink # assistant professor at teaching universities
        current_allocation[cursor] = num + min(4, numsink)
        cursor += 1
    end
    blankcount = 0

    # BEGIN MONTE CARLO REALLOCATION ROUTINE
    while true
        # attempt to reallocate academic institutions to a random spot
        temp_allocation = copy(current_allocation)
        k = rand(1:length(academic_institutions))
        @inbounds temp_allocation[k] = rand(delete!(Set(1:num), temp_allocation[k]))
        # check if the new assignment is better
        test_objective, estimated_means = bucket_estimate(temp_allocation, sample, num, numsink,b)
        if test_objective < cur_objective
            print(test_objective, " ")
            blankcount = 0
            cur_objective = test_objective
            best_mat = estimated_means
            current_allocation = temp_allocation
        else
            blankcount += 1
            if blankcount % 1000 == 0
                print(blankcount, " ")
            end
        end
        if blankcount == 100000
            return cur_objective, best_mat, current_allocation
        end
    end
end
@time est_obj, est_mat, est_alloc = doit(out, collect(academic), collect(acd_sink), collect(gov_sink), collect(pri_sink),
    collect(tch_sink), institutions, NUMBER_OF_TYPES, NUMBER_OF_SINKS)
println("that is how long doit takes")
jj=JSON.string(est_mat)
open("est_mat1.json","w") do f
    write(f,jj)
end 

function bucket_extract(assign, A::Matrix{Int64}, num, numsink)
    T = zeros(Int64, num + numsink, num)
    for i in 1:size(A)[1], j in 1:size(A)[2]
            @inbounds T[(num + 1) * (assign[j] - 1) + assign[i]] += A[i, j]
    end
    return T
end


est_mat = bucket_extract(est_alloc, out, NUMBER_OF_TYPES, NUMBER_OF_SINKS);M = est_mat

# the new placements matrix
placement_rates = zeros(Int64, (TOTAL_DISTRIBUTIONS, NUMBER_OF_TYPES))
#row sums in the estimated matrix
ovector = sum(M, dims=1)
# row sums reordered highest to lowest
svector = sortslices(ovector,dims=2, rev=true) 
#println(svector)
#println(length(ovector))
# a mapping from current row index to the index it should have in the new matrix
o = Dict{}()
for i in 1:length(ovector)
    for k in 1:length(svector)
        if ovector[1,i] == svector[1,k]
            o[i] = k
            break
        end
    end
end 
#println(o)
P = zeros(Int64, (TOTAL_DISTRIBUTIONS, NUMBER_OF_TYPES))
#shuffle the cells for the tier to tier placements
for i in 1:NUMBER_OF_TYPES
    for j in 1:NUMBER_OF_TYPES
        placement_rates[o[i],o[j]] = M[i,j]
    end
end
#shuffle the cells for tier to sink placements (separate since sink row indices don't change)
for i in NUMBER_OF_TYPES+1:NUMBER_OF_TYPES+NUMBER_OF_SINKS
    for j in 1:NUMBER_OF_TYPES
        placement_rates[i,o[j]] = M[i,j]
    end
end

for i in 1:NUMBER_OF_TYPES, j in 1:NUMBER_OF_TYPES
    if i > j # not a diagonal and only check once
        if placement_rates[i, j] <= placement_rates[j, i]
            println("FAULT: hiring ", i, " with graduating ", j, ": downward rate: ", placement_rates[i, j], ", upward rate: ", placement_rates[j, i])
        end
    end
end
println("Check Complete")

function name_to_oid(institution_name::String, institutions::Dict, organizations::Dict)
    oids = String[]
    institution_id = String
    for k in keys(institutions)
        if institutions[k] == institution_name
            institution_id = k
            break
            #push!(oids,k)
        end
    end
    for k in keys(organizations)
        if organizations[k] == institution_id
            push!(oids, k)
        end
    end
return institution_id, oids
end

function save_type(tier, oids, stm)
    for oid in oids
        DB.execute(stm, [tier, oid])
    end
end

n = 0
B = Set{String}()

if SAVE_TO_DATABASE
    d = DB.connect(MySQL.Connection,cfg["host"], cfg["user"], cfg["password"], db =cfg["database"], port = parse(Int64,cfg["port"]))
    query = "drop table if exists type_distribution"
    DB.execute(d, query)
    query = "create table type_distribution (id int auto_increment primary key, type int, oid int,created timestamp default CURRENT_TIMESTAMP )"
    DB.execute(d, query)
    query = "insert into type_distribution set type=?,oid=?"
    stm = DB.prepare(d, query)
end
for j in 1:NUMBER_OF_TYPES
    println("Type ", j)
    println()
    i = 1
    for entry in est_alloc
        if entry == j
            push!(B,institutions[i])
            iid, oids = name_to_oid(institutions[i],institution_mapping, oid_mapping)
            println(institutions[i]," ",oids)
            if(length(oids)) == 0
                println("*****Error in data****")
                global n
                n += 1
            end
            if SAVE_TO_DATABASE
                save_type(j, oids, stm)
            end
        end
        i += 1
    end
    println(n," errors counted")
    println()
end
if SAVE_TO_DATABASE
    DB.close(d)
end

n = 0
B = Set{String}()
if SAVE_TO_DATABASE
    d = DB.connect(MySQL.Connection,cfg["host"], cfg["user"], cfg["password"], db =cfg["database"], port = parse(Int64,cfg["port"]))
    query = "insert into type_distribution set type=?,oid=?"
    stm = DB.prepare(d, query)
end
for j in NUMBER_OF_TYPES+1:NUMBER_OF_SINKS+NUMBER_OF_TYPES
    println("SINK ", j - NUMBER_OF_TYPES)
    println()
    i = 1
    for entry in est_alloc
        if entry == j 
            if occursin("(private sector)", institutions[i])
                ch = 17
            elseif (!occursin("(private sector)", institutions[i]) && !occursin("(public sector)", institutions[i]) 
                    && !occursin("(academic sink)", institutions[i]))
                ch = 0
            else ch = 16
            end
            if !(institutions[i][1:prevind(institutions[i], end,ch)] in B)
                iid, oids = name_to_oid(institutions[i][1:prevind(institutions[i],end,ch)],institution_mapping, oid_mapping)
                println(institutions[i]," ", oids)
                if length(oids) == 0
                    println("****** error in data*****")
                    n +=1
                end
                if SAVE_TO_DATABASE
                    save_type(j, oids, stm)
                end
                push!(B, institutions[i][1:prevind(institutions[i], end,ch)])
            end
        end
        i += 1
    end
    println()
    global  n
    println(n," errors counted")
end
try
DB.close(d)
catch
    print("all done")
end 