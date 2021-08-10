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

# Change to True if using SQL connector
use_sql = True

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
    json_name = 'to_from_with_gender_time.json'
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

app = dash.Dash(__name__, external_stylesheets=external_stylesheets)

app.layout = html.Div([html.Div([
    dcc.Location(id='url', refresh=False),
    html.H1("Economics Ph.D. Placement Data", style={"text-align": "center"}),
    html.Div(
        [html.H6(("Author: Amedeus D'Souza, Vancouver School of Economics",
                  html.Br(),
                  "Contributor: Jingze (Alex) Dong, Vancouver School of Economics"),
                 style={"float": "left", "margin": "auto"}),
         html.Div(html.A(html.Button("Learn More"),
                         href='https://github.com/michaelpetersubc/mapinator/blob/master/mapinator_readme/mapinator_readme.md'),
                  style={"float": "right", "margin": "auto"})
         ]),
    html.Br(),
    html.Br(),
    html.Br(),
    html.Br(),
    # workathon title in count_colour
    html.H2(('Cumulative Count for Workathon : ', count),
            # href='https://w4s-2021.github.io/',
            style={'text-align': 'center', 'color': count_colour, "margin": "auto"}),
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
         html.Div(["Placement Year",
                   dcc.Dropdown(id="slidey",
                                options=vals,
                                value=date.today().year,
                                placeholder="Select Year of Placement")],
                  style={"width": "20%", "float": "left", "margin": "auto"}),
         html.Div(["Female Placement Only",
                   dcc.Dropdown(id="female",
                                options=[{"label": "False", "value": "0"},
                                         {"label": "True", "value": "1"}],
                                value="0",
                                placeholder="Select True for Female Only Placements"
                                )],
                  style={"width": "20%", "float": "left", "margin": "auto"})], className="row"),
    dcc.Graph(id="my_map", figure={}),
    dash_table.DataTable(id="my_cloud", page_size=10,
                         columns=[{"name": "graduated-from", "id": "from_shortname"},
                                  {"name": "gradschool-rank", "id": "rank"},
                                  {"name": "hired-by", "id": "to_shortname"},
                                  {"name": "hired-by-rank", "id": "to_rank"},
                                  {"name": "position-type", "id": "position_name"},
                                  {'name': 'gender', 'id': 'gender'},
                                  {'name': 'placement year', 'id': 'year'}],
                         style_table={'height': '350px', 'overflowY': 'auto'}),
    html.Br(),
    # placeholder for putting donor logos
    html.Img(
        src='https://raw.githubusercontent.com/VoliCrank/pics/main/ubc_logo.jpg',
        alt='picture broken...', style={'width': '20%'})
])])


@app.callback(Output('select_inst', 'value'), Input('url', 'pathname'))
def display_page(pathname):
    if pathname is None or len(pathname) <= 1:
        return 0
    oid = pathname[1:]
    print(len(oid), oid.isdigit())
    if len(oid) > 0 and oid.isdigit() and len(inst_data[inst_data['from_oid'] == int(oid)]) > 0:
        return int(oid)
    return 0


# call back app that updates values corresponding to labels above
@app.callback([Output("my_map", "figure"),
               Output("my_cloud", "data")],
              [Input("select_inst", "value"),
               Input("select_stuff", "value"),
               Input("select_sector", "value"),
               Input("slidey", "value"),
               Input('female', 'value')])
def mapinator(inst_val, spec_val, sect_val, year_val, female_val):
    if type(inst_val) is int:
        inst_val = [inst_val]

    iterated_data = inst_data.loc[
        ((inst_data["from_oid"].isin(inst_val)) |
         (inst_data["from_oid"] > max(inst_val) * max(inst_val) * max(inst_val))) &
        ((inst_data["category_id"] == int(spec_val)) | (inst_data["category_id"] > int(spec_val) * 400)) &
        ((inst_data["postype"] == int(sect_val)) | (inst_data["postype"] > int(sect_val) * 40)) &
        ((inst_data['startdate'].dt.year == int(year_val)) | (-1 == int(year_val)))]

    if female_val is not None and int(female_val) == 1:
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
