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
import datetime
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
        'select * from to_data t join from_data f on t.aid=f.aid where to_latitude is not null and latitude is not null and category_id in (1,2,6,7,10,12,13,15,16,23)')
    inst_data = pd.DataFrame(db_cursor.fetchall())
else:
    # requires json file to be in the same folder as this file
    p = os.getcwd()
    json_name = 'to_from_with_gender_time.json'
    p = p + '\\' + json_name
    inst_data = pd.read_json(p)

workathondate = datetime.datetime(2021, 7, 2)
count_colour = 'navy'

inst_data["startdate"] = pd.to_datetime(inst_data["startdate"])  # convert object to datetime

inst_data["rank"][inst_data["rank"].notnull()] = "Rank: " + inst_data["rank"][inst_data["rank"].notnull()].astype(str)
inst_data["to_rank"][inst_data["to_rank"].notnull()] = "Rank: " + inst_data["to_rank"][
    inst_data["to_rank"].notnull()].astype(str)

inst_data["rank"] = inst_data["rank"].fillna(" ")
inst_data["to_rank"] = inst_data["to_rank"].fillna(" ")

# preprocess data to reduce load time
f = lambda row: row.split('.')[0].split(" ")[1]
inst_data['rank'] = inst_data['rank'].apply(f)
inst_data['to_rank'] = inst_data['to_rank'].apply(f)
columns = ['from_shortname', 'rank', 'to_shortname', 'to_rank', 'position_name', 'gender']
inst_data['meta'] = inst_data[columns].to_dict(orient='records')
inst_data['from_uni'] = inst_data['from_shortname'] + '<br>' + inst_data['rank']
inst_data['to_uni'] = inst_data['to_shortname'] + '<br>' + inst_data['to_rank']

external_stylesheets = ['https://codepen.io/chriddyp/pen/bWLwgP.css']
listfoo = [{"label": "From Institutions - All", "value": 0}]
listextendfoo = [{"label": i, "value": j} for i, j in
                 sorted(set(zip(inst_data.from_shortname, inst_data.from_oid)))]  # inst_data.from_institution_name
# FIXME ideally instead of shortname we create new column inst_data_from_fullname = inst_data.from_institution_name
#  + " - " + inst_data.from_department also + "(" + inst_data.from_shortname + ")"
#  either via MySQL or Python conditional on server; same for to
fooextender = listfoo.extend(listextendfoo)

vals = [{'label': 'All Years', 'value': '-1'}]
for yr in range(2008, date.today().year + 1):
    vals.append({"label": yr, "value": yr})

app_server = Flask(__name__)

app = dash.Dash(__name__, external_stylesheets=external_stylesheets)
app.layout = html.Div([html.H1("Economics Ph.D. Placement Data", style={"text-align": "center"}),
                       html.Div([html.H6("Author: Amedeus D'Souza, Vancouver School of Economics",
                                         style={"float": "left", "margin": "auto"}),
                                 html.Div(html.A(html.Button("Learn More"),
                                                 href='https://github.com/michaelpetersubc/mapinator/blob/master/mapinator_readme/mapinator_readme.md'),
                                          style={"float": "right", "margin": "auto"})]),
                       html.Br(),
                       html.Br(),
                       html.H2(('Cumulative Count Since ', workathondate.strftime('%x'), ' : ',
                                len(inst_data[inst_data['created_at'] >= workathondate])),
                               style={'text-align': 'center', 'color': count_colour}),
                       html.Br(),
                       html.Br(),
                       # html.Div([html.H5("Red: moved east to west.", style = {"color": "red"}), html.H5("Blue: moved west to east.", style = {"color": "blue"})]),
                       # html.Div("Either the From Institution or the Primary Fields must be set to something other than All for this to work"),
                       html.Div(
                           [html.Div(["Applicant Institution", dcc.Dropdown(id="select_inst",
                                                                            options=listfoo,
                                                                            value=67,  # UBC
                                                                            multi=True,
                                                                            placeholder="Select institutions where applicants graduated from"
                                                                            )],
                                     style={"width": "20%", "float": "left", "margin": "auto"}),
                            html.Div(["Primary Specialization", dcc.Dropdown(id="select_stuff",
                                                                             options=[{
                                                                                 "label": "Primary Specializations - All",
                                                                                 "value": "0"},
                                                                                 {"label": "Development; Growth",
                                                                                  "value": "1"},
                                                                                 {"label": "Econometrics",
                                                                                  "value": "2"},
                                                                                 {"label": "Finance",
                                                                                  "value": "6"},
                                                                                 {"label": "Industrial Organization",
                                                                                  "value": "7"},
                                                                                 {
                                                                                     "label": "Labor; Demographic Economics",
                                                                                     "value": "10"},
                                                                                 {"label": "Macroeconomics; Monetary",
                                                                                  "value": "12"},
                                                                                 {"label": "Microeconomics",
                                                                                  "value": "13"},
                                                                                 {"label": "Theory",
                                                                                  "value": "15"},
                                                                                 {"label": "Behavioral Economics",
                                                                                  "value": "16"},
                                                                                 {"label": "Political Economics",
                                                                                  "value": "23"}],
                                                                             value="0",
                                                                             placeholder="Select primary specialization"
                                                                             )],
                                     style={"width": "20%", "float": "left", "margin": "auto"}),
                            html.Div(["Position Type", dcc.Dropdown(id="select_sector",
                                                                    options=[
                                                                        {"label": "Position Type - All", "value": "0"},
                                                                        {"label": "Assistant Professor", "value": "1"},
                                                                        {"label": "Associate Professor", "value": "2"},
                                                                        {"label": "Full Professor", "value": "3"},
                                                                        {"label": "Professor (Unspecified)",
                                                                         "value": "4"},
                                                                        {"label": "Temporary Lecturer", "value": "5"},
                                                                        {"label": "Post-Doc", "value": "6"},
                                                                        {"label": "Lecturer", "value": "7"},
                                                                        {"label": "Consultant", "value": "8"},
                                                                        {"label": "Other Academic", "value": "9"},
                                                                        {"label": "Other Non-Academic", "value": "10"},
                                                                        {"label": "Tenured Professor", "value": "11"},
                                                                        {"label": "Assistant or Associate Professor",
                                                                         "value": "13"},
                                                                        {
                                                                            "label": "Visiting Professor/Lecturer/Instructor",
                                                                            "value": "15"}],
                                                                    value="0",
                                                                    placeholder="Select position type"
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
                            html.Div(["Placement Year", dcc.Dropdown(id="slidey",
                                                                     options=vals,
                                                                     value=date.today().year,
                                                                     placeholder="Select year of placement")],
                                     style={"width": "20%", "float": "left", "margin": "auto"}),
                            html.Div(["Female Placement Only", dcc.Dropdown(id="female",
                                                                            options=[
                                                                                {"label": "False", "value": "0"},
                                                                                {"label": "True", "value": "1"}],
                                                                            value="0",
                                                                            placeholder="Select True for female only placements"
                                                                            )],
                                     style={"width": "20%", "float": "left", "margin": "auto"})], className="row"),
                       html.Br(),
                       html.Br(),
                       dcc.Graph(id="my_map", figure={}),
                       dcc.Tabs(
                           [dcc.Tab(label='Placement Details',
                                    children=[dash_table.DataTable(id="my_cloud", page_size=10,
                                                                   style_table={'height': '350px', 'overflowY': 'auto'},
                                                                   columns=[{"name": "graduated-from",
                                                                             "id": "from_shortname"},
                                                                            {"name": "gradschool-rank", "id": "rank"},
                                                                            {"name": "hired-by", "id": "to_shortname"},
                                                                            {"name": "hired-by-rank", "id": "to_rank"},
                                                                            {"name": "position-type",
                                                                             "id": "position_name"},
                                                                            {'name': 'gender', 'id': 'gender'}])]),
                            dcc.Tab(label='Leaderboard for Workathon',
                                    children=[dash_table.DataTable(id='ranks', page_size=10,
                                                                   columns=[{'name': 'rank', 'id': 'rank'},
                                                                            {'name': 'creator id', 'id': 'created_by'}],
                                                                   style_table={'height': '350px',
                                                                                'overflowY': 'auto'})])]),
                       html.Br(),
                       # placeholder for putting donor logos
                       html.Img(
                           src='https://raw.githubusercontent.com/VoliCrank/pics/main/ubc_logo.jpg',
                           alt='picture broken...', style={'width': '20%'})
                       ])


# ,
@app.callback([Output("my_map", "figure"), Output("my_cloud", "data"), Output('ranks', 'data')],
              [Input("select_inst", "value"),

               Input("select_stuff", "value"),
               Input("select_sector", "value"),
               Input("slidey", "value"),
               Input('female', 'value')])
def mapinator(inst_val, spec_val, sect_val, year_val, female_val):
    # customize display options
    workathon = True
    line_colour = 'navy'
    to_colour = 'green'
    from_colour = 'darkgoldenrod'

    if type(inst_val) is int:
        inst_val = [inst_val]

    iterated_data = inst_data.loc[
        ((inst_data["from_oid"].isin(inst_val)) | (
                inst_data["from_oid"] > max(inst_val) * max(inst_val) * max(inst_val))) &
        ((inst_data["category_id"] == int(spec_val)) | (inst_data["category_id"] > int(spec_val) * 400)) &
        ((inst_data["postype"] == int(sect_val)) | (inst_data["postype"] > int(sect_val) * 40))]

    if not -1 == int(year_val):
        iterated_data = iterated_data[iterated_data['startdate'].dt.year == int(year_val)]
    if int(female_val) != 0:
        iterated_data = iterated_data[(iterated_data['gender'] == 'Female')]

    # create initial empty figure
    fig = go.Figure(go.Scattergeo())
    fig.update_layout(height=800)

    # set up vectorized loading
    (lons, lats) = prep_data(iterated_data)
    # load lines
    fig.add_trace(go.Scattergeo(lon=lons, lat=lats, mode='lines', showlegend=False,
                                line=dict(width=1, color=line_colour)))

    if workathon:
        work_data = iterated_data[iterated_data['created_at'] >= workathondate]
        (lons, lats) = prep_data(work_data)
        fig.add_trace(go.Scattergeo(lon=lons, lat=lats, mode='lines',
                                    line=dict(width=1, color='red')))

    # format university display names on the dots

    # add to_uni dots
    fig.add_trace(go.Scattergeo(lon=iterated_data['to_longitude'], lat=iterated_data['to_latitude'],
                                hoverinfo="text", text=iterated_data['to_uni'], mode="markers", name='hired by',
                                marker=dict(size=2.5, color=to_colour,
                                            line=dict(width=3, color=to_colour))))

    # add from_uni dots
    fig.add_trace(go.Scattergeo(lon=iterated_data['longitude'], lat=iterated_data['latitude'], hoverinfo="text",
                                text=iterated_data['from_uni'], mode="markers", name='graduated from',
                                marker=dict(size=2.5, symbol='circle', color=from_colour,
                                            line=dict(width=3, color=from_colour))))

    fig.update_layout(showlegend=True,
                      geo=dict(projection_type="equirectangular", showland=True, landcolor="whitesmoke",
                               countrycolor="silver", showcountries=True, showlakes=True, showcoastlines=True,
                               coastlinecolor="darkgrey", lakecolor="white",
                               oceancolor="white"))

    # format data for table

    table_data = iterated_data['meta'].to_list()

    return fig, table_data, make_rankings(inst_data)


# magic vectorization stuff from the internet
def prep_data(df):
    lons = np.empty(3 * len(df))
    lons[::3] = df['longitude']
    lons[1::3] = df['to_longitude']
    lons[2::3] = None
    lats = np.empty(3 * len(df))
    lats[::3] = df['latitude']
    lats[1::3] = df['to_latitude']
    lats[2::3] = None
    return (lons, lats)


def make_rankings(inst_data):
    rankings = {1: '\U0001F3C6', 2: '\U0001F947', 3: '\U0001F948', 4: '\U0001F949'}
    work_data = inst_data[inst_data['created_at'] >= workathondate]
    k = work_data['created_by'].value_counts().index
    for i in range(len(k) - 4):
        rankings[i + 5] = i + 5
    data = []
    for i in range(len(k)):
        rank = rankings[i + 1]
        data.append({'created_by': k[i], 'rank': rank})
    return data


server = app.server

if __name__ == "__main__":
    app.run_server(debug=True)
