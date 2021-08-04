import dash
import dash_core_components as dcc
import dash_html_components as html
from dash.dependencies import Input, Output

import numpy as np

import requests
text = requests.get("https://raw.githubusercontent.com/michaelpetersubc/mapinator/master/estimation/REPORT.md").text

# can adjust this part to use mySQL instead of json later, although the files are small
import json
with open("consolidated_rankings.json") as f:
    rankings = json.load(f)

with open("index_to_id.txt") as f:
    index_to_id = [int(a, 0) for a in f.readline().split(", ")]

with open("placements.txt") as f:
    placements = np.array([[int(b, 0) for b in a.split()] for a in f.readline().split("; ")])

with open("index_to_type.txt") as f:
    index_to_type = [int(a, 0) for a in f.readline().split(", ")]

app = dash.Dash(__name__, external_stylesheets = ['https://codepen.io/chriddyp/pen/bWLwgP.css'], title = "Estimation", suppress_callback_exceptions=True, update_title=None)

url_bar = html.Div([
    dcc.Location(id = 'url', refresh = False),
    html.Div(id = 'page-content')
])

homepage = html.Div([
    html.Div([
        html.Div([html.Br()], className = "two columns"),   
        html.Div([
            html.H1("Economics Job Market Network", style = {"text-align": "center"}),
            dcc.Markdown(text, dangerously_allow_html = True)], className = "eight columns"),
        html.Div([html.Br()], className = "two columns"),   
    ], className = "row"),
    dcc.Markdown("---"),
    dcc.Markdown("Source and data explanations: [GitHub Repository](https://github.com/michaelpetersubc/mapinator)\n\nWebsite Author: James Yuming Yu, Vancouver School of Economics", style = {"text-align": "center"}),
    html.Div([html.Img(src='https://raw.githubusercontent.com/VoliCrank/pics/main/ubc_logo.jpg', alt='ubc_logo', style={"width": "20%"})], style = {"text-align": "center"})
])

institution_page = html.Div([
    html.H1("Economics Job Market Network", style = {"text-align": "center"}),
    html.Div([
        html.Div([html.Br()], className = "one column"),   
        html.Div(id = "inst", className = "ten columns"),
        html.Div([html.Br()], className = "one column"),   
    ], className = "row"),
    html.Div([
        html.Div([html.Br()], className = "two columns"),   
        html.Div(id = "inst2", className = "eight columns"),
        html.Div([html.Br()], className = "two column"),   
    ], className = "row"),
    dcc.Markdown("---"),
    dcc.Markdown("Source and data explanations: [GitHub Repository](https://github.com/michaelpetersubc/mapinator)\n\nWebsite Author: James Yuming Yu, Vancouver School of Economics", style = {"text-align": "center"}),
    html.Div([html.Img(src='https://raw.githubusercontent.com/VoliCrank/pics/main/ubc_logo.jpg', alt='ubc_logo', style={"width": "20%"})], style = {"text-align": "center"})
    ])

app.layout = url_bar
app.validation_layout = html.Div([
    url_bar,
    homepage,
    institution_page
])

def pois(mean, val):
    return (mean**val) * np.exp(-mean) / np.math.factorial(val)

@app.callback(Output('page-content', 'children'), Input('url', 'pathname'))
def display_page(pathname):
    if "/institution/" in pathname:
        return institution_page
    return homepage

@app.callback(Output("inst", "children"), Output("inst2", "children"),Input('url', 'pathname'))
def display_institution(pathname):
    institution_id = pathname.split("/")[-1]
    if institution_id in rankings:
        my_type = rankings[institution_id]['vse-ejm']
        index_of_institution = index_to_id.index(int(institution_id))
        overall_outbound_self_rates = [0, 0, 0, 0, 0, 0, 0, 0]
        overall_inbound_self_rates = [0, 0, 0, 0]
        personal_outbound_self_rates = [0, 0, 0, 0, 0, 0, 0, 0]
        personal_inbound_self_rates = [0, 0, 0, 0]
        convert = [0, 3, 2, 4, 1, 5, 6, 7, 8]
        for i in range(placements.shape[0]):
            for j in range(placements.shape[1]):
                if convert[index_to_type[j]] == my_type:
                    overall_outbound_self_rates[convert[index_to_type[i]] - 1] += placements[i, j]
                if convert[index_to_type[i]] == my_type:
                    overall_inbound_self_rates[convert[index_to_type[j]] - 1] += placements[i, j]
            personal_outbound_self_rates[convert[index_to_type[i]] - 1] += placements[i, index_of_institution]

        for j in range(placements.shape[1]):
            personal_inbound_self_rates[convert[index_to_type[j]] - 1] += placements[index_of_institution, j]
        
        type_sizes = [0, 0, 0, 0, 0, 0, 0, 0]
        for i in range(len(index_to_type)):
            type_sizes[convert[index_to_type[i]] - 1] += 1

        average_outbound_self_rates = [round(elt/type_sizes[ind], 2) for ind, elt in enumerate(overall_outbound_self_rates)]
        average_inbound_self_rates = [round(elt/type_sizes[ind], 2) for ind, elt in enumerate(overall_inbound_self_rates)]

        all_outbound_self_rates = [[], [], [], [], [], [], [], []]
        all_inbound_self_rates = [[], [], [], []]
        for i in range(placements.shape[0]):
            for j in range(placements.shape[1]):
                if convert[index_to_type[j]] == my_type:
                    all_outbound_self_rates[convert[index_to_type[i]] - 1].append(placements[i, j])
                if convert[index_to_type[i]] == my_type:
                    all_inbound_self_rates[convert[index_to_type[j]] - 1].append(placements[i, j])

        outbound_variance = [sum([(a - average_outbound_self_rates[i])**2 for a in all_outbound_self_rates[i]]) / (len(all_outbound_self_rates[i]) - 1) for i in range(len(all_outbound_self_rates))]
        inbound_variance = [sum([(a - average_inbound_self_rates[i])**2 for a in all_inbound_self_rates[i]]) / (len(all_inbound_self_rates[i]) - 1) for i in range(len(all_inbound_self_rates))]
        name = rankings[institution_id]["name"]
        labels = ["Type 1", "Type 2", "Type 3", "Type 4", "Non-Professor Academic Positions", "Government", "Private Sector", "Teaching Institutions"]
        newline = '\n\n'
        star = ' \* '

        top_outbound_t = list(np.argsort(placements[:, index_of_institution]))
        top_outbound_t.reverse()
        top_outbound = []
        for i in top_outbound_t:
            count = placements[i, index_of_institution]
            if str(index_to_id[i]) in rankings and count != 0:
                top_outbound.append(rankings[str(index_to_id[i])]["name"] + f" ({count} placement{['', 's'][int(count != 1)]})")

        top_inbound_t = list(np.argsort(placements[index_of_institution, :]))
        top_inbound_t.reverse()
        top_inbound = []
        for i in top_inbound_t:
            count = placements[index_of_institution, i]
            if str(index_to_id[i]) in rankings and count != 0:
                top_inbound.append(rankings[str(index_to_id[i])]["name"] + f" ({count} placement{['', 's'][int(count != 1)]})")

        return [
            html.Div([
                html.Div([
                    html.H3(name),
                    html.H5(f"VSE-EJM Categorization: Type {my_type}"),
                    dcc.Markdown(f"**[REPEC](https://ideas.repec.org/top/top.econdept.html)** Rank: **{rankings[institution_id]['repec']}**"),
                    dcc.Markdown(f"**[Tilburg University](https://econtop.uvt.nl/rankingsandbox.php)** Rank: **{rankings[institution_id]['tilburg']}**"),
                ], className = "four columns"),
                html.Div([
                    html.H5(f"Top Three institutions where graduates from here are hired:"),
                    dcc.Markdown("\n\n".join(top_outbound[:3]))
                ], className = "four columns"),
                html.Div([
                    html.H5(f"Top Three institutions this institution hires graduates from:"),
                    dcc.Markdown("\n\n".join(top_inbound[:3]))
                ], className = "four columns"),
            ], className = "row"),
            dcc.Markdown("---"),], [
            html.H3(f"Specific Metrics for {name}", style = {"text-align": "center"}),
            html.Div([
                dcc.Markdown(f"#### Total Placements from {name} to:\n{newline.join([': '.join(b) for b in zip(labels, [str(a) for a in personal_outbound_self_rates])])}", className = "six columns"),
                dcc.Markdown(f"#### Average Placements from a generic Type {my_type} institution to:\n{newline.join([': '.join(b) for b in zip(labels, [str(a) for a in average_outbound_self_rates])])}", className = "six columns"),
            ], className = "row"),
            dcc.Markdown(f"###### Probability of actual placements given average: {star.join([str(round(pois(m, v), 2)) for m, v in zip(average_outbound_self_rates, personal_outbound_self_rates)])} = {round(np.prod([pois(m, v) for m, v in zip(average_outbound_self_rates, personal_outbound_self_rates)]), 4)}"),
            dcc.Markdown(f"#### Sample Variance in Placements from Type {my_type} to:\n{newline.join([': '.join(b) for b in zip(labels, [str(round(a, 2)) for a in outbound_variance])])}", style = {"text-align": "center"}),
            dcc.Markdown("---"),
            html.Div([
                dcc.Markdown(f"#### Total Placements to {name} from:\n{newline.join([': '.join(b) for b in zip(labels, [str(a) for a in personal_inbound_self_rates])])}", className = "six columns"),
                dcc.Markdown(f"#### Average Placements to a generic Type {my_type} institution from:\n{newline.join([': '.join(b) for b in zip(labels, [str(a) for a in average_inbound_self_rates])])}", className = "six columns"),
            ], className = "row"),
            dcc.Markdown(f"###### Probability of actual placements given average: {star.join([str(round(pois(m, v), 2)) for m, v in zip(average_inbound_self_rates, personal_inbound_self_rates)])} = {round(np.prod([pois(m, v) for m, v in zip(average_inbound_self_rates, personal_inbound_self_rates)]), 4)}"),
            dcc.Markdown(f"#### Sample Variance in Placements to Type {my_type} from:\n{newline.join([': '.join(b) for b in zip(labels, [str(round(a, 2)) for a in inbound_variance])])}", style = {"text-align": "center"}),
            dcc.Markdown("---"),
            html.H3(f"General Metrics for Type {my_type}", style = {"text-align": "center"}),
            dcc.Markdown(f"#### Total Placements from all Type {my_type} institutions to:\n{newline.join([': '.join(b) for b in zip(labels, [str(a) for a in overall_outbound_self_rates])])}"),
            dcc.Markdown("---"),
            dcc.Markdown(f"#### Total Placements to all Type {my_type} institutions from:\n{newline.join([': '.join(b) for b in zip(labels, [str(a) for a in overall_inbound_self_rates])])}"),
            ]
    return [html.H3("Institution not found.")], []

if __name__ == "__main__":
    app.run_server(debug = False)