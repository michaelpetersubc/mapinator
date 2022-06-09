#### Script originally written by Kieran Weaver
#### This version Jonah Heyl June 9 2022
import webbrowser as wb 
from tkinter import *
import os
import time
from datetime import datetime

try:
    import requests
except:
    os.system("pip install requests")

root = Tk()




#### Constants
slice_length=3
SEARCH = "https://www.google.com/search?q={}+{}+{}+economics+cv" 
#Linkedin_SEARCH = "https://www.google.com/search?q={}+{}+Linkedin" 

####Set up 
slices=[]
count=-1
ticker=0


####makes slices




def make_file():
    headers = {
        'Content-Type': 'application/x-www-form-urlencoded',
    }
    data = 'client_id=support_token_server&client_secret=4support_token2work&grant_type=password&username={}&password={}'
    print('Enter your ejm user name')
    user = input().strip(' ')
    print('Enter your ejm password')
    password= input().strip(' ')
    data=data.format(user, password)

    response = requests.post('https://support.econjobmarket.org/oauth2/token', headers=headers, data=data)
    ref_token=response.json()['refresh_token']
    print(ref_token)

    data = {
        'client_id': 'support_token_server',
        'client_secret': '4support_token2work',
        'grant_type': 'refresh_token',
        'refresh_token':ref_token,
    }

    response = requests.post('https://support.econjobmarket.org/oauth2/token', data=data)

    access_toke= response.json()['access_token']
    
    
    list=[user,password,ref_token,access_toke]
    with open  ('user.dat','w') as f:
        for word in list:
            f.write(word+" ")
    return  access_toke


def file_y_n():
    try:
        with open('user.dat','r') as f:
            u=f.read().split(' ')
    except(FileNotFoundError):
        make_file()
        with open('user.dat','r') as f:
            u=f.read().split(' ')
    return list(u)
    



def get_data(access_toke): 
    
    headers = {
    'Accept': 'application/json',
    'Authorization': 'Bearer '+ access_toke,
    }

    response = requests.get('https://support.econjobmarket.org/api/slice', headers=headers)
    #response1 = requests.get('https://support.econjobmarket.org/api/slice', headers=headers)
    #response2 = requests.get('https://support.econjobmarket.org/api/slice', headers=headers)
    slice=response.json()
    #slice1= response1.json()
    #slice2=response2.json()
    print(slice)
    try:
        d=slice[0]
    except:
        return 0

    return slice



def get_new_access_toke(user,passoword):

    headers = {
        'Content-Type': 'application/x-www-form-urlencoded',
    }
    data = 'client_id=support_token_server&client_secret=4support_token2work&grant_type=password&username={}&password={}'
    data=data.format(user, passoword)

    response = requests.post('https://support.econjobmarket.org/oauth2/token', headers=headers, data=data)
    ref_token=response.json()['refresh_token']

    data = {
        'client_id': 'support_token_server',
        'client_secret': '4support_token2work',
        'grant_type': 'refresh_token',
        'refresh_token':ref_token,
    }

    response = requests.post('https://support.econjobmarket.org/oauth2/token', data=data)
    try:
        access_toke= response.json()['access_token']
        
    except(KeyError):
        return 2
    
    list=[user,passoword,ref_token,access_toke]
    with open  ('user.dat','w') as f:
        for word in list:
            f.write(word+" ")
    return access_toke



def run():
    sd =file_y_n()
    a=get_data(sd[3])
    if (a== 0):
        b=get_new_access_toke(sd[0],sd[1])      
        a=get_data(b)
    return(a)


b=0

def starter():
    global b
    dict = run()
    #list=response.json()
    dict1=run()
    dict2=run()
    b=time.perf_counter()
    list=dict+dict1+dict2
    
    i=0
    curslice = []

    for row in list:
        curslice.append([row['aid'], row['fname'], row['lname'],row['degreeinst'] ])
        i += 1
        if i == slice_length: #this sets the length of the currslice
            slices.append(curslice[:])
            curslice = []
            i = 0
    if len(curslice):
        slices.append(curslice[:])
   


def func(count): 
    data=slices[count]
    searcher(data)

     
def searcher(data): #opens the tabs
    print(data)
    for i in range(0,3):
        row = data[i]
        if len(row):
            wb.open_new_tab(f"https://support.econjobmarket.org/candidate/{row[0]}")
            wb.open_new_tab(SEARCH.format(row[1],row[2],row[3]))




#the button
root.geometry("500x500")
root.title("VSE EJM Data Tool")

count=0

def do_things():
    global count
    starter()
    count+=1
    func(count)
    #display.configure(text=len(slices)-count)


def button_press():
    global count, b
    a=time.perf_counter()
    if one:
        root.after([20000, 0][a-b> 20], do_things)
'''
    if two:
        global ticker
        ticker+=1
        display.configure(text=ticker)
'''
display = LabelFrame(root,bg="blue", width="462", height="60")
display.pack()

one = Button(root, text="Add slice", width="15", height="5",command=button_press)
one.pack(side="bottom")

#two = Button(root, text="ticker", width="15", height="5", command=button_press)
#two.pack(side="left")

root.mainloop()
