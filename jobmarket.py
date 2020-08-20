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
external_stylesheets = ['https://codepen.io/chriddyp/pen/bWLwgP.css']
listfoo = [{"label": "From Institutions - All", "value": 0}]
listextendfoo = [{"label": i, "value": j} for i, j in sorted(set(zip(inst_data.from_institution_name, inst_data.from_oid)))]
fooextender = listfoo.extend(listextendfoo)

vals = []
for yr in range(2008,date.today().year):
    vals.append({"label": yr, "value":yr})

app_server = Flask(__name__)

app = dash.Dash(__name__, external_stylesheets = external_stylesheets)
app.layout = html.Div([
                       html.H1("Economics Phd Placement Data", style = {"text-align": "center"}),
                       #html.Div([html.H5("Red: moved east to west.", style = {"color": "red"}), html.H5("Blue: moved west to east.", style = {"color": "blue"})]),
                       html.Div("Either the organization or the category must be set to something other than All for this to work"),
                       dcc.Dropdown(id = "select_inst",
                                    options = listfoo,
                                    value = 0,
#                                    multi = True
                                    ),
                       dcc.Dropdown(id = "select_stuff",
                                    options = [{"label": "Primary Specializations - All", "value": 0}, 
                                               {"label": "Development; Growth", "value": 1},
                                               {"label": "Econometrics", "value": 2},
                                               {"label": "Finance", "value": 6},
                                               {"label": "Industrial Organization", "value": 7},
                                               {"label": "Labor; Demographic Economics", "value": 10},
                                               {"label": "Macroeconomics; Monetary", "value": 12},
                                               {"label": "Microeconomics", "value": 13},
                                               {"label": "Theory", "value": 15},
                                               {"label": "Behavioral Economics", "value": 16},
                                               {"label": "Political Economics", "value": 23}],
                                    value = 0
                                    ),
                       dcc.Dropdown(id = "select_sector",
                                    options = [{"label": "Recruiter Types - All", "value": "0"},
                                               {"label": "Academic organization (economics department)", "value": "1"},
                                               {"label": "Academic organization (business school)", "value": "2"},
                                               {"label": "Academic organization (agricultural/resource economics department)", "value": "3"},
                                               {"label": "Academic organization (other than econ, business, or ag econ)", "value": "4"},
                                               {"label": "Government agency or commission", "value": "5"},
                                               {"label": "Private (for profit) business or organization", "value" : "6"},
                                               {"label": "Private (non-profit) business or organization", "value": "7"},
                                               {"label": "Other type of organization", "value": "8"},
                                               {"label": "Advertising agency or executive recruiter", "value": "9"},
                                               {"label": "Human Resources department of educational or non-profit institution", "value": "10"},
                                               {"label": "Human Resources department of for-profit organization", "value": "11"},
                                               {"label": "Personal", "value": "12"}],
                                    value = "0"
                                    ),
                       dcc.Dropdown(id = "slidey", 
                                    options = vals,
                                    value = 2019
                                 ),
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
    if (int(q) == 0) & (int(x) == 0):
        q = 67
    iterated_data = inst_data.loc[((inst_data["startdate"].dt.year == int(z)) | ((inst_data["startdate"].dt.year > int(z)*int(z)))) &\
                                  ((inst_data["from_oid"] == int(q)) | ((inst_data["from_oid"] > int(q)*int(q)*int(q)))) &\
                                  ((inst_data["category_id"] == int(x)) | ((inst_data["category_id"] > int(x)*400))) &\
                                  ((inst_data["recruiter_type"] == int(y)) | ((inst_data["recruiter_type"] > int(y)*40)))]

    fig = go.Figure()
    cloud_data = []
    fig.update_layout(height=800)
    for row in iterated_data.itertuples():
        if row.longitude <= row.to_longitude:
               colors = "red"
        else: colors = "blue"
        fig.add_trace(go.Scattergeo(lon = [row.longitude, row.to_longitude], lat = [row.latitude, row.to_latitude], mode = "lines", line = dict(width = 1, color = colors)))
        fig.add_trace(go.Scattergeo(lon = [row.to_longitude], lat = [row.to_latitude], hoverinfo = "text", text = [row.to_name + ' ' + str(row.to_rank)], mode = "markers", marker = dict(size = 0.1, color = "rgb(128, 0, 128)", line = dict(width = 3, color = "rgba(68, 68, 68, 0)"))))
        fig.add_trace(go.Scattergeo(lon = [row.longitude], lat = [row.latitude], hoverinfo = "text", text = [row.from_institution_name + ' ' + str(row.rank)], mode = "markers", marker = dict(size = 0.1, color = "rgb(128, 0, 128)", line = dict(width = 3, color = "rgba(68, 68, 68, 0)"))))
        cloud_data.append(dict({'aid':row.aid,'from_institution_name':row.from_institution_name,'rank':row.rank,'to_name':row.to_name,'to_rank':row.to_rank}))

    fig.update_layout(showlegend = False, geo = dict(projection_type = "equirectangular", showland = True, landcolor = "rgb(243, 243, 243)", countrycolor = "rgb(204, 204, 204)", showcountries = True, showlakes = True, showcoastlines = True)) #title_text = "category_id_" + str(x) + ": " + data_subsets[x].name.unique()[0], 


    cloud_columns = [{"name":"aid","id":"aid"},{"name":"graduated-from","id":"from_institution_name"},{"name":"gradschool-rank","id":"rank"},{"name":"hired-by","id":"to_name"},{"name":"hired-by-rank","id":"to_rank"}]
    return fig, cloud_data, cloud_columns
    

server = app.server

if __name__ == "__main__":
  app.run_server(debug=True)


