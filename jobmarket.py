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

db_connection = sql.connect(host='127.0.0.1', database='econjobmarket_research', user='amedeus', password='amedeus')

db_cursor = db_connection.cursor(dictionary=True)

db_cursor.execute('select * from to_data t join from_data f on t.aid=f.aid where to_latitude is not null and latitude is not null and category_id in (1,2,6,7,10,12,13,15,16,23)')

inst_data = pd.DataFrame(db_cursor.fetchall())

inst_data["startdate"] = pd.to_datetime(inst_data["startdate"]) #convert object to datetime

inst_data["rank"] = inst_data["rank"].fillna(" ")
inst_data["to_rank"] = inst_data["to_rank"].fillna(" ")

external_stylesheets = ['https://codepen.io/chriddyp/pen/bWLwgP.css']
listfoo = [{"label": "From Institutions - All", "value": 0}]
listextendfoo = [{"label": i, "value": j} for i, j in sorted(set(zip(inst_data.from_shortname, inst_data.from_oid)))] #inst_data.from_institution_name
#FIXME ideally instead of shortname we create new column inst_data_from_fullname = inst_data.from_institution_name + " - " + inst_data.from_department also + "(" + inst_data.from_shortname + ")" either via MySQL or Python conditional on server; same for to
fooextender = listfoo.extend(listextendfoo)

vals = []
for yr in range(2008,date.today().year + 1):
    vals.append({"label": yr, "value":yr})

app_server = Flask(__name__)

app = dash.Dash(__name__, external_stylesheets = external_stylesheets)
app.layout = html.Div([html.H1("Economics Ph.D. Placement Data", style = {"text-align": "center"}),
                       html.Div([html.H6("Author: Amedeus D'Souza, Vancouver School of Economics", style = {"float": "left", "margin":"auto"}),
                       html.Div(html.A(html.Button("Learn More"), href='https://github.com/michaelpetersubc/mapinator/blob/master/mapinator_readme/mapinator_readme.md'), style={"float": "right", "margin": "auto"})]),
                       html.Br(),
                       html.Br(),
                       html.Br(),
                       #html.Div([html.H5("Red: moved east to west.", style = {"color": "red"}), html.H5("Blue: moved west to east.", style = {"color": "blue"})]),
                       #html.Div("Either the From Institution or the Primary Fields must be set to something other than All for this to work"),
                       html.Div([html.Div(["Institutions Where Applicants Graduated From", dcc.Dropdown(id = "select_inst",
                                    options = listfoo,
                                    value = 67, #UBC
                                    multi = True,
                                    placeholder = "Select institutions where applicants graduated from"
                                    )], style = {"width": "25%", "float": "left", "margin": "auto"}),
                       html.Div(["Primary Specialization", dcc.Dropdown(id = "select_stuff",
                                    options = [{"label": "Primary Specializations - All", "value": "0"}, 
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
                                    value = "0",
                                    placeholder = "Select primary specialization"
                                    )], style = {"width": "25%", "float": "left", "margin": "auto"}),
                       html.Div(["Position Type", dcc.Dropdown(id = "select_sector",
                                    options = [{"label": "Position Type - All", "value": "0"}, 
                                               {"label": "Assistant Professor", "value": "1"},
                                               {"label": "Associate Professor", "value": "2"},
                                               {"label": "Full Professor", "value": "3"},
                                               {"label": "Professor Any Level", "value": "4"},
                                               {"label": "Temporary Lecturer", "value": "5"},
                                               {"label": "Post-Doc", "value": "6"},
                                               {"label": "Lecturer", "value": "7"},
                                               {"label": "Consultant", "value": "8"},
                                               {"label": "Other Academic", "value": "9"},
                                               {"label": "Other Non-Academic", "value": "10"},
                                               {"label": "Tenured Professor", "value": "11"},
                                               {"label": "Assistant or Associate Professor", "value": "13"},
                                               {"label": "Visiting Professor/Lecturer/Instructor", "value": "15"}],
                                    value = "0",
                                    placeholder = "Select position type"
                                    )], style = {"width": "25%", "float": "left", "margin": "auto"}),    
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
                       html.Div(["Placement Year", dcc.Dropdown(id = "slidey", 
                                    options = vals,
                                    value = 2019,
                                    placeholder = "Select year of placement")], style = {"width": "25%", "float": "left", "margin": "auto"})], className = "row"),
                       html.Br(),
                       dcc.Graph(id = "my_map", figure = {}),
                       dash_table.DataTable(id = "my_cloud")
                      ])
#, 
@app.callback([Output("my_map", "figure"), Output("my_cloud", "data"), Output("my_cloud", "columns")],
                                           [Input("select_inst", "value"),
                                           Input("select_stuff", "value"),
                                           Input("select_sector", "value"),
                                           Input("slidey", "value")])
def mapinator(q, x, y, z):
    global inst_data
#     if (int(q) == 0) & (int(x) == 0):
#         q = 67

    if type(q) is int:
        q = [q]
    elif type(q) is list:
        q = q

    iterated_data = inst_data.loc[((inst_data["startdate"].dt.year == int(z)) | ((inst_data["startdate"].dt.year > int(z)*int(z)))) &\
                                  ((inst_data["from_oid"].isin(q)) | ((inst_data["from_oid"] > max(q)*max(q)*max(q)))) &\
                                  ((inst_data["category_id"] == int(x)) | ((inst_data["category_id"] > int(x)*400))) &\
                                  ((inst_data["postype"] == int(y)) | ((inst_data["postype"] > int(y)*40)))]
#pairing "all" with specific institutions gives specific institutions
                                   
    fig = go.Figure()
    cloud_data = []
    fig.update_layout(height=800)
    for row in iterated_data.itertuples():
#        if row.longitude <= row.to_longitude:
#               colors = "red"
#        else: colors = "blue"
        colors = "navy"
        fig.add_trace(go.Scattergeo(lon = [row.longitude, row.to_longitude], lat = [row.latitude, row.to_latitude], mode = "lines", line = dict(width = 1, color = colors)))
        fig.add_trace(go.Scattergeo(lon = [row.to_longitude], lat = [row.to_latitude], hoverinfo = "text", text = [row.to_shortname + '; Rank: ' + str(row.to_rank).split(".")[0]], mode = "markers", marker = dict(size = 2.5, color = "navy", line = dict(width = 3, color = "darkgoldenrod")))) #row.to_name
        fig.add_trace(go.Scattergeo(lon = [row.longitude], lat = [row.latitude], hoverinfo = "text", text = [row.from_shortname + '; Rank: ' + str(row.rank).split(".")[0]], mode = "markers", marker = dict(size = 2.5, color = "navy", line = dict(width = 3, color = "darkgoldenrod")))) #row.from_institution_name
        cloud_data.append(dict({'from_shortname':row.from_shortname,'rank':row.rank,'to_shortname':row.to_shortname,'to_rank':row.to_rank, 'position_name': row.position_name})) #'aid':row.aid #'from_institution_name':row.from_institution_name

    fig.update_layout(showlegend = False, geo = dict(projection_type = "equirectangular", showland = True, landcolor = "whitesmoke", countrycolor = "silver", showcountries = True, showlakes = True, showcoastlines = True, coastlinecolor = "darkgrey", lakecolor = "white", oceancolor = "white")) #title_text = "category_id_" + str(x) + ": " + data_subsets[x].name.unique()[0], 


    cloud_columns = [{"name":"graduated-from","id":"from_shortname"},{"name":"gradschool-rank","id":"rank"},{"name":"hired-by","id":"to_shortname"},{"name":"hired-by-rank","id":"to_rank"}, {"name":"position-type","id":"position_name"}] #{"name":"aid","id":"aid"},
    return fig, cloud_data, cloud_columns
    

server = app.server

if __name__ == "__main__":
  app.run_server(debug=True)


