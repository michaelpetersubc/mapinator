module bootstrap_functions

using JSON
using PrettyTables, HTTP

export process_data

function get_data(url)
    resp = HTTP.get(url);
    es = String(resp.body)
    return placements = JSON.parse(es)
end

function process_data(YEAR_INTERVAL)
    url = "https://support.econjobmarket.org/api/placement_data"
    placements = get_data(url);
    return placements
end
function sampler(pls, sample_size)
    placements = []
    m = length(pls)
    y = 1
    while y < sample_size + 1
        push!(placements, pls[rand(1:m)])
        y = y + 1
    end
    oid_mapping = Dict{}()
    institution_mapping = Dict{}()
    academic = Set{}()
    academic_to = Set{}()
    academic_builder = Vector{}()
    sink_builder = Vector{}()
    for placement in placements
        push!(academic, placement["from_institution_name"])
        if placement["position_name"] == "Assistant Professor"
                push!(academic_to, placement["to_name"])
        end
        oid_mapping[placement["from_oid"]] = placement["from_institution_id"]
        oid_mapping[placement["to_oid"]] = placement["to_institution_id"]
        institution_mapping[placement["from_institution_id"]] = placement["from_institution_name"]
        institution_mapping[placement["to_institution_id"]] = placement["to_name"]
        if placement["postype"] == "1"
            push!(academic_builder, placement)
        else
            push!(sink_builder, placement)
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
    postdoc = Set{}()
    lecturer = Set{}()
    for outcome in sink_builder
        # CODE global academic, other_placements, pri_sink, gov_sink, acd_sink
        if outcome["recruiter_type"] in ["6", "7"]
            # private sector: for and not for profit
            push!(pri_sink, string(outcome["to_name"], " (private sector)"))
        elseif outcome["recruiter_type"] == "5"
            # government institution
            push!(gov_sink, string(outcome["to_name"], " (public sector)"))
        elseif outcome["postype"] == "6"
            #postdoc
            push!(postdoc, string(outcome["to_name"], " (postdoc)"))
        elseif outcome["postype"] in ["5", "7"]
            #postdoc
            push!(lecturer, string(outcome["to_name"], " (lecturer)"))
        else
            # everything else including terminal academic positions
            push!(acd_sink, string(outcome["to_name"], " (academic sink)"))
        end
    end
    return academic_builder, sink_builder, academic, acd_sink, gov_sink, pri_sink, tch_sink, postdoc, lecturer, institution_mapping
end

end