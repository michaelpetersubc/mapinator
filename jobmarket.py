import os
import IPython
from datetime import date
import mysql.connector as sql
import pandas as pd
import plotly
import plotly.graph_objects as go
from flask import Flask
import dash
import dash_core_components as dcc
import dash_html_components as html
import dash_table
from dash.dependencies import Input, Output
from dotenv import load_dotenv
from datetime import datetime, timedelta
import numpy as np
import json

import warnings
# highly recommend commenting out the following line whenever editing this file
warnings.simplefilter(action='ignore', category=Warning)

# Change to True if using SQL connector
use_sql = True

name_to_iid = {}
with open("type_data.json") as f:
    rankings = json.load(f)
    for key in rankings["specific"]:
        name_to_iid[rankings["specific"][key]["name"]] = key

reverse_search = {}
with open("oid_lookup.json") as f:
    oid_lookup = json.load(f)
    for name in oid_lookup:
        for oid in oid_lookup[name]:
            if name in name_to_iid:
                reverse_search[oid] = name_to_iid[name]

global inst_data

if use_sql:
    load_dotenv()
    db_connection = sql.connect(host='127.0.0.1', database=os.environ.get("foodatabase"),
                                user=os.environ.get("foousername"), password=os.environ.get("foopassword"))
    db_cursor = db_connection.cursor(dictionary=True)
    db_cursor.execute(
        'select * from to_data t join from_data f on t.aid=f.aid where to_latitude is not null and latitude is not null and to_oid !=893')
    inst_data = pd.DataFrame(db_cursor.fetchall())
else:
    # requires json file to be in the same folder as this file
    p = os.getcwd()
    json_name = 'name_of_json_file.json'
    p = p + '\\' + json_name
    inst_data = pd.read_json(p)


def preprocess(df):
    # convert object to datetime
    df["startdate"] = pd.to_datetime(df["startdate"])

    df["rank"][df["rank"].notnull()] = "Rank: " + df["rank"][df["rank"].notnull()].astype(str)
    df["to_rank"][df["to_rank"].notnull()] = "Rank: " + df["to_rank"][df["to_rank"].notnull()].astype(str)

    df["rank"] = df["rank"].fillna(" ")
    df["to_rank"] = df["to_rank"].fillna(" ")

    f = lambda row: row.split('.')[0].split(" ")[1]
    df['rank'] = df['rank'].apply(f)
    df['to_rank'] = df['to_rank'].apply(f)
    df['year'] = df['startdate'].dt.year
    columns = ['from_shortname', 'rank', 'to_shortname', 'to_rank', 'position_name', 'gender', 'year']
    df['meta'] = df[columns].to_dict(orient='records')
    df['from_uni'] = df['from_shortname'] + '<br>' + df['rank']
    df['to_uni'] = df['to_shortname'] + '<br>' + df['to_rank']
    df = df.sort_values(by=['year'], ascending=False)
    # cols = ['longitude', 'latitude', 'to_longitude', 'to_latitude']
    # df = df.dropna(subset = cols)

    return df


inst_data = preprocess(inst_data)

# workathon attributes, offset by 8 to change to pacific time
displaydate = datetime(2021, 7, 2)
workathondate = displaydate - timedelta(hours=8)
workathonend = displaydate + timedelta(days=3) + timedelta(hours=8)
count_colour = 'navy'
count = 5154
# cols = ['longitude', 'latitude', 'to_longitude', 'to_latitude']
# inst_data = inst_data.dropna(subset = cols)
external_stylesheets = ['https://codepen.io/chriddyp/pen/bWLwgP.css']
listfoo = [{"label": "From Institutions - All", "value": 0}, {"label": "Workathon 2021", "value": -1}]
listextendfoo = [{"label": i, "value": j} for i, j in
                 sorted(set(zip(inst_data.from_shortname, inst_data.from_oid)))]  # inst_data.from_institution_name
# FIXME ideally instead of shortname we create new column inst_data_from_fullname = inst_data.from_institution_name
#  + " - " + inst_data.from_department also + "(" + inst_data.from_shortname + ")"
#  either via MySQL or Python conditional on server; same for to
fooextender = listfoo.extend(listextendfoo)

vals = []
for yr in range(inst_data['year'].min(), inst_data['year'].max() + 1):
    vals.append({"label": yr, "value": yr})
vals.append({'label': 'All Years', 'value': '-1'})
vals.reverse()
app_server = Flask(__name__)

app = dash.Dash(__name__, external_stylesheets=external_stylesheets, title = "Mapinator")

app.layout = html.Div([html.Div([
    dcc.Location(id='url', refresh=False),
    html.H1("Economics Ph.D. Placement Data", style={"text-align": "center"}),
    # workathon title in count_colour
    html.H5(('Cumulative Count for Workathon : ', count),
            # href='https://w4s-2021.github.io/',
            style={'text-align': 'center', 'color': count_colour, "margin": "auto"}),
    html.Div(
        [
         html.Div(html.A(html.Button("About the Project", style = {"color": "blue"}),
                         href='https://support.econjobmarket.org/git_page/econjobmarket%2Bapi_documentation/mapinator/mapinator.md'),
                  style={"float": "left", "margin": "auto"}),
         html.Div(html.A(html.Button("About the Mapinator", style = {"color": "blue"}),
                         href='https://github.com/michaelpetersubc/mapinator/blob/master/mapinator_readme/mapinator_readme.md'),
                  style={"float": "right", "margin": "auto"})
         ]),
    html.Br(),
    html.Br(),
    html.Div(
        [html.Div(["Applicant Institution",
                   dcc.Dropdown(id="select_inst",
                                options=listfoo,
                                value=0,  # All Inst
                                multi=True,
                                placeholder="Select Applicant Institution"
                                )],
                  style={"width": "20%", "float": "left", "margin": "auto"}),
         html.Div(["Primary Specialization",
                   dcc.Dropdown(id="select_stuff",
                                options=[{"label": "Primary Specializations - All", "value": "0"},
                                         {"label": "Development; Growth", "value": "1"},
                                         {"label": "Econometrics", "value": "2"},
                                         {"label": "Finance", "value": "6"},
                                         {"label": "Industrial Organization", "value": "7"},
                                         {"label": "Labor; Demographic Economics", "value": "10"},
                                         {"label": "Macroeconomics; Monetary", "value": "12"},
                                         {"label": "Microeconomics", "value": "13"},
                                         {"label": "Theory", "value": "15"},
                                         {"label": "Behavioral Economics", "value": "16"},
                                         {"label": "Political Economics", "value": "23"}],
                                value="0",
                                placeholder="Select Primary Specialization"
                                )],
                  style={"width": "20%", "float": "left", "margin": "auto"}),
         html.Div(["Position Type",
                   dcc.Dropdown(id="select_sector",
                                options=[
                                    {"label": "Position Type - All", "value": "0"},
                                    {"label": "Assistant Professor", "value": "1"},
                                    {"label": "Associate Professor", "value": "2"},
                                    {"label": "Full Professor", "value": "3"},
                                    {"label": "Professor (Unspecified)", "value": "4"},
                                    {"label": "Temporary Lecturer", "value": "5"},
                                    {"label": "Post-Doc", "value": "6"},
                                    {"label": "Lecturer", "value": "7"},
                                    {"label": "Consultant", "value": "8"},
                                    {"label": "Other Academic", "value": "9"},
                                    {"label": "Other Non-Academic", "value": "10"},
                                    {"label": "Tenured Professor", "value": "11"},
                                    {"label": "Assistant or Associate Professor", "value": "13"},
                                    {"label": "Visiting Professor/Lecturer/Instructor",
                                     "value": "15"}],
                                value="1",
                                placeholder="Select Position Type"
                                )],
                  style={"width": "20%", "float": "left", "margin": "auto"}),
         #                        dcc.Dropdown(id = "select_sector",
         #                                     options = [{"label": "Recruiter Types - All", "value": "0"},
         #                                                {"label": "Academic organization (economics department)", "value": "1"},
         #                                                {"label": "Academic organization (business school)", "value": "2"},
         #                                                {"label": "Academic organization (agricultural/resource economics department)", "value": "3"},
         #                                                {"label": "Academic organization (other than econ, business, or ag econ)", "value": "4"},
         #                                                {"label": "Government agency or commission", "value": "5"},
         #                                                {"label": "Private (for profit) business or organization", "value" : "6"},
         #                                                {"label": "Private (non-profit) business or organization", "value": "7"},
         #                                                {"label": "Other type of organization", "value": "8"},
         #                                                {"label": "Advertising agency or executive recruiter", "value": "9"},
         #                                                {"label": "Human Resources department of educational or non-profit institution", "value": "10"},
         #                                                {"label": "Human Resources department of for-profit organization", "value": "11"},
         #                                                {"label": "Personal", "value": "12"}],
         #                                     value = "0",
         #                                     placeholder = "Select a type of recruiter"
         #                                     ),
         html.Div(["Women-Only Placements",
                   dcc.Dropdown(id="women",
                                options=[{"label": "False", "value": "0"},
                                         {"label": "True", "value": "1"}],
                                value="0",
                                placeholder="Select True for Women-Only Placements"
                                )],
                  style={"width": "20%", "float": "left", "margin": "auto"}),
         html.Div(["Placement Year",
                   dcc.Dropdown(id="slidey",
                                options=vals,
                                value=date.today().year,
                                placeholder="Select Year of Placement")],
                  style={"width": "10%", "float": "left", "margin": "auto"}),
        html.Div(["Applicant Focus",
                   dcc.Dropdown(id="focus",
                                options=[{"label": "Graduates", "value": "0"},
                                         {"label": "Hires", "value": "1"}],
                                value="0",
                                placeholder="Select Focus for Applicants"
                                )],
                  style={"width": "10%", "float": "left", "margin": "auto"})], className="row"),
    dcc.Graph(id="my_map", figure={}),
    dash_table.DataTable(id="my_cloud", page_size=10,
                         columns=[{"name": "graduated-from", "id": "from_shortname"},
                                  {"name": "gradschool-rank", "id": "rank"},
                                  {"name": "hired-by", "id": "to_shortname"},
                                  {"name": "hired-by-rank", "id": "to_rank"},
                                  {"name": "position-type", "id": "position_name"},
                                  {'name': 'sex', 'id': 'gender'},
                                  {'name': 'placement year', 'id': 'year'}],
                         style_table={'overflowY': 'auto'}),
    html.Br(),
    html.Div(id = "bonus-data"),
    dcc.Markdown("---"),
    dcc.Markdown("##### Author: Amedeus Akira Dsouza, Vancouver School of Economics\n\nContributor: Jingze (Alex) Dong, Vancouver School of Economics\n\nContributor: James Yuming Yu, Vancouver School of Economics", style = {"text-align": "center"}),
    html.Div([html.Img(src='https://raw.githubusercontent.com/VoliCrank/pics/main/ubc_logo.jpg', alt='ubc_logo', style={"width": "20%"})], style = {"text-align": "center"})
])])


@app.callback(Output('url', 'pathname'), Input('focus', 'value'), Input('url', 'pathname'))
def focus(val, pathname):
    if val == "1" and not pathname.endswith("/r"):
        return pathname.rstrip("/") + "/r"
    elif val == "0" and pathname.endswith("/r"):
        return pathname.rstrip("/r")
    else:
        return pathname

@app.callback(Output('select_inst', 'value'), Output('slidey', 'value'), Input('url', 'pathname'))
def display_page(pathname):
    path = pathname.split("/")
    if pathname is None or len(path) < 2:
        return [0], "2021"

    oid = path[1]
    if oid.isdigit() and len(inst_data[inst_data['from_oid'] == int(oid)]) > 0:
        return [int(oid)], "2021"
    elif oid == "institution" and len(path) > 2 and path[2] in rankings["specific"] and rankings["specific"][path[2]]["name"] in oid_lookup:
        return oid_lookup[rankings["specific"][path[2]]["name"]], "-1"
    return [0], "2021"


# call back app that updates values corresponding to labels above
@app.callback([Output("my_map", "figure"),
               Output("my_cloud", "data")],
              [Input("select_inst", "value"),
               Input("select_stuff", "value"),
               Input("select_sector", "value"),
               Input("slidey", "value"),
               Input('women', 'value'), 
               Input('url', 'pathname')])
def mapinator(inst_val, spec_val, sect_val, year_val, women_val, pathname):
    if not year_val:
        year_val = "-1"
    if not sect_val:
        sect_val = "0"
    if not spec_val:
        spec_val = "0"
    
    if inst_val == []:
        # if someone wipes all the fields, default to All
        inst_val = [0]

    selection = ["from_oid", "to_oid"][int(pathname.endswith("/r"))]
    iterated_data = inst_data.loc[
        ((inst_data[selection].isin(inst_val)) |
         (inst_data[selection] > max(inst_val) * max(inst_val) * max(inst_val))) &
        ((inst_data["category_id"] == int(spec_val)) | (inst_data["category_id"] > int(spec_val) * 400)) &
        ((inst_data["postype"] == int(sect_val)) | (inst_data["postype"] > int(sect_val) * 40)) &
        ((inst_data['startdate'].dt.year == int(year_val)) | (-1 == int(year_val)))]

    if women_val is not None and int(women_val) == 1:
        iterated_data = iterated_data[(iterated_data['gender'] == 'Female')]
    if -1 in inst_val:
        iterated_data = iterated_data[
            (iterated_data['created_at'] >= workathondate) & (iterated_data['created_at'] <= workathonend)]
    iterated_data = add_labels(iterated_data)
    # create initial empty figure
    fig = go.Figure(go.Scattergeo())
    fig.update_layout(height=800)
    plot_graph(fig, iterated_data)

    table_data = iterated_data['meta'].to_list()

    return fig, table_data

@app.callback(Output('bonus-data', 'children'), Input('url', 'pathname'), Input('select_inst', 'value'))
def render_bonus(pathname, oids):
    institution_id = None
    for oid in oids:
        if oid in reverse_search and reverse_search[oid] in rankings["specific"] and reverse_search[oid] != "714":
            institution_id = reverse_search[oid]
            break
    else:
        path = pathname.split("/")
        if (path[1] == "institution" and len(path) > 2 and path[2] in rankings["specific"]):
            institution_id = path[2]

    if not institution_id:
        return []

    data = rankings["specific"][institution_id]
    name = data["name"]
    my_type = data['vse-ejm']
    top_outbound = data["top_three_to"]
    top_inbound = data["top_three_from"]
    labels = ["Type 1", "Type 2", "Type 3", "Type 4", "Non-Professor Academic Positions", "Government", "Private Sector", "Teaching Institutions"]
    newline = '\n\n'
    return [html.Div([
        html.Div([html.Br()], className = "one column"),   
        html.Div([
            html.Div([
                html.Div([
                    html.H3(name),
                    html.H5(f"VSE-EJM Categorization: Type {my_type}"),
                    dcc.Markdown(f"**[REPEC](https://ideas.repec.org/top/top.econdept.html)** Rank: **{data['repec']}**"),
                    dcc.Markdown(f"**[Tilburg University](https://econtop.uvt.nl/rankingsandbox.php)** Rank: **{data['tilburg']}**"),
                ], className = "four columns"),
                html.Div([
                    html.H5(f"Top Three institutions where graduates from here are hired:"),
                    dcc.Markdown("\n\n".join(top_outbound))
                ], className = "four columns"),
                html.Div([
                    html.H5(f"Top Three institutions this institution hires graduates from:"),
                    dcc.Markdown("\n\n".join(top_inbound))
                ], className = "four columns"),
            ], className = "row"),
            dcc.Markdown("---"),
        ], className = "ten columns"),
        html.Div([html.Br()], className = "one column"),   
    ], className = "row"),
    html.Div([
        html.Div([html.Br()], className = "two columns"),   
        html.Div([ 
            html.H3(f"Specific Metrics for {name}", style = {"text-align": "center"}),
            html.Div([
                dcc.Markdown(f"#### Total Placements from {name} to:\n{newline.join([': '.join(b) for b in zip(labels, [str(a) for a in data['total_placements_to']])])}", className = "six columns"),
                dcc.Markdown(f"#### Average Placements from a generic Type {my_type} institution to:\n{newline.join([': '.join(b) for b in zip(labels, [str(a) for a in rankings['generic'][my_type - 1]['average_to']])])}", className = "six columns"),
            ], className = "row"),
            dcc.Markdown(f"###### Normalized Likelihood of placements given average: {data['likelihood_to']}"),
            dcc.Markdown(f"#### Sample Variance in Placements from Type {my_type} to:\n{newline.join([': '.join(b) for b in zip(labels, [str(round(a, 2)) for a in rankings['generic'][my_type - 1]['variance_to']])])}", style = {"text-align": "center"}),
            dcc.Markdown("---"),
            html.Div([
                dcc.Markdown(f"#### Total Placements to {name} from:\n{newline.join([': '.join(b) for b in zip(labels, [str(a) for a in data['total_placements_from']])])}", className = "six columns"),
                dcc.Markdown(f"#### Average Placements to a generic Type {my_type} institution from:\n{newline.join([': '.join(b) for b in zip(labels, [str(a) for a in rankings['generic'][my_type - 1]['average_from']])])}", className = "six columns"),
            ], className = "row"),
            dcc.Markdown(f"###### Normalized Likelihood of placements given average: {data['likelihood_from']}"),
            dcc.Markdown(f"#### Sample Variance in Placements to Type {my_type} from:\n{newline.join([': '.join(b) for b in zip(labels, [str(round(a, 2)) for a in rankings['generic'][my_type - 1]['variance_from']])])}", style = {"text-align": "center"}),
            dcc.Markdown("---"),
            html.H3(f"General Metrics for Type {my_type}", style = {"text-align": "center"}),
            dcc.Markdown(f"#### Total Placements from all Type {my_type} institutions to:\n{newline.join([': '.join(b) for b in zip(labels, [str(a) for a in rankings['generic'][my_type - 1]['total_to']])])}"),
            dcc.Markdown("---"),
            dcc.Markdown(f"#### Total Placements to all Type {my_type} institutions from:\n{newline.join([': '.join(b) for b in zip(labels, [str(a) for a in rankings['generic'][my_type - 1]['total_from']])])}"),
        ], className = "eight columns"),
        html.Div([html.Br()], className = "two column"),   
    ], className = "row"),
    ]



# creates labels for hovering over the dots on the map
def add_labels(df):
    from_size = df.value_counts(subset=['from_shortname'])
    to_size = df.value_counts(subset=['to_shortname'])
    df['from_size'] = df['from_shortname'].apply(lambda x: int(from_size[x]))
    df['to_size'] = df['to_shortname'].apply(lambda x: int(to_size[x]))
    cols = ['from_size', 'to_size']
    df[cols] = df[cols].fillna(value=0)
    df['from_uni'] = df['from_uni'] + '<br>' + 'Graduated ' + df['from_size'].astype(str) + ' student(s)'
    df['to_uni'] = df['to_uni'] + '<br>' + 'Hired ' + df['to_size'].astype(str) + ' graduate(s)'
    return df


# plots dots and lines
def plot_graph(fig, df):
    line_colour = 'navy'
    to_colour = 'green'
    from_colour = 'darkgoldenrod'
    if len(df) != 0:
        add_lines(fig, df, line_colour)
        # add from_uni dots
        scale = lambda x: x ** 0.8
        fig.add_trace(go.Scattergeo(lon=df['longitude'], lat=df['latitude'], hoverinfo="text",
                                    text=df['from_uni'], mode="markers", name='graduated from',
                                    marker=dict(size=df['from_size'].apply(scale), color=from_colour,
                                                line=dict(width=3, color=from_colour))))
        # add to_uni dots
        fig.add_trace(go.Scattergeo(lon=df['to_longitude'], lat=df['to_latitude'], hoverinfo="text",
                                    text=df['to_uni'], mode="markers", name='hired by',
                                    marker=dict(size=df['to_size'].apply(scale), color=to_colour,
                                                line=dict(width=3, color=to_colour))))
    # customize the map
    fig.update_layout(showlegend=True,
                      geo=dict(projection_type="equirectangular", showland=True, landcolor="whitesmoke",
                               countrycolor="silver", showcountries=True, showlakes=True, showcoastlines=True,
                               coastlinecolor="darkgrey", lakecolor="white", oceancolor="white"))


# magic vectorization stuff from the internet, adds lines to the map
def add_lines(fig, df, colour):
    lons = np.empty(3 * len(df))
    lons[::3] = df['longitude']
    lons[1::3] = df['to_longitude']
    lons[2::3] = None
    lats = np.empty(3 * len(df))
    lats[::3] = df['latitude']
    lats[1::3] = df['to_latitude']
    lats[2::3] = None
    fig.add_trace(go.Scattergeo(lon=lons, lat=lats, mode='lines', showlegend=False,
                                line=dict(width=1, color=colour)))


server = app.server

if __name__ == "__main__":
    app.run_server(debug=True)
