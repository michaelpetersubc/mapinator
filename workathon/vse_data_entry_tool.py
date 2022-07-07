#getting the packages

import os

try:
    import webbrowser as wb 
except:
    os.system("pip install webbrowser")

try:
    from tkinter import *
except:
    os.system("pip install tkinter")

try:
    import time
except:
    os.system("pip install time")

try:
    import requests
except:
    os.system("pip install requests")


root=Tk()


#### This is what you might want to change,
slice_length=3 #how many tabs are made
SEARCH = "https://www.google.com/search?q={}+{}+{}+economics+cv"  #what is searched in google


####Set up 
slices=[]



####Collects user detials

def user_detials():
    print('Enter your ejm user name')
    user = input().strip(' ')
    print('Enter your ejm password')
    password= input().strip(' ')
    return user,password


#creates a file with user detials and tokens

def make_file(user="NA", password="NA",get_input=False):
    headers = {
        'Content-Type': 'application/x-www-form-urlencoded',
    }
    data = 'client_id=support_token_server&client_secret=4support_server2work&grant_type=password&username={}&password={}'

    if get_input==False:
        user,password = user_detials()
    
    data=data.format(user,password)

    ref_token = requests.post('https://support.econjobmarket.org/oauth2/token', headers=headers, data=data).json()['refresh_token']



    data = {
        'client_id': 'support_token_server',
        'client_secret': '4support_server2work',
        'grant_type': 'refresh_token',
        'refresh_token':ref_token,
    }

    access_token = requests.post('https://support.econjobmarket.org/oauth2/token', data=data).json()['access_token']

    
    
    l=[user,password,ref_token,access_token]
    with open  ('user.dat','w') as f:
        for word in l:
            f.write(word+" ")
    return  access_token

#reads in the user file
def file_y_n():
    try:
        with open('user.dat','r') as f:
            u=f.read().split(' ')
    except(FileNotFoundError):
        make_file()
        with open('user.dat','r') as f:
            u=f.read().split(' ')   
    return u
    


#what actaully sends requests for data to the server
def get_data(access_token): 
    
    headers = {
    'Accept': 'application/json',
    'Authorization': 'Bearer '+ access_token,
    }

    slice = requests.get('https://support.econjobmarket.org/api/slice', headers=headers).json()

    
    try:
        slice[0]
    except:
        return 0
    return slice






#this runs all of the above functions in the desired sequence
def run():
    sd =file_y_n()
    a=get_data(sd[3])
    if (a== 0):
        b=make_file(sd[0],sd[1],True)
        a=get_data(b)
    return(a)


#This is what happens when the button is clicked

b=0

def starter():
    global b
    dict = run();dict1=run();dict2=run()
    b=time.perf_counter()
    list=dict+dict1+dict2
    
    i=0
    curslice = []

    for row in list:
        curslice.append([row['aid'], row['fname'], row['lname'],row['degreeinst'] ])
        i += 1
        if i == slice_length:
            slices.append(curslice[:])
            curslice = [];i = 0
    if len(curslice):
        slices.append(curslice[:])
   


def func(count): 
    data=slices[count]
    searcher(data)

def searcher(data): #opens the tabs

    for i in range(0,3):
        row = data[i]
        if len(row):
            wb.open_new_tab(f"https://support.econjobmarket.org/candidate/{row[0]}")
            wb.open_new_tab(SEARCH.format(row[1],row[2],row[3]))




#The GUI    
root.geometry("800x800")
root.title("VSE Data Entry Tool")

count=0

def do_things():
    global count
    starter()
    count+=1
    func(count)


def button_press():
    global count, b
    a=time.perf_counter()
    if one:
        root.after([20000, 0][a-b> 20], do_things)


display = LabelFrame(root,bg="blue", width="462", height="60")
display.pack()

one = Button(root, text="Add slice", width="15", height="5",command=button_press)
one.pack(side="bottom")


root.mainloop()