import json,time,urllib.request
BASE="http://api.det-app.ru"
stamp=int(time.time()*1000)
def req(method,path,token=None,body=None):
    data=None if body is None else json.dumps(body,ensure_ascii=False).encode("utf-8")
    h={"Content-Type":"application/json; charset=utf-8"}
    if token: h["Authorization"]=f"Bearer {token}"
    r=urllib.request.Request(BASE+path,data=data,headers=h,method=method)
    with urllib.request.urlopen(r,timeout=30) as resp:
        raw=resp.read().decode("utf-8")
        return None if (not raw or raw.strip()=="null") else json.loads(raw)
login=req("POST","/auth/login",body={"login":"owner@demo.det-app.ru","password":"DetAppAdmin2026!"})
token=login["access_token"]
# ensure shift open
cur=req("GET","/cash/shifts/current",token)
if not cur or cur.get("status")!="open":
    cur=req("POST","/cash/shifts/open",token,{"openings":{},"note":"scenario"})
# Scenario A: wash
phoneA=f"901{stamp%10000000:07d}"
cA=req("POST","/crm/clients",token,{"name":f"Сценарий Мойка {stamp%10000}","phone":phoneA,"is_vip":False})
carA=req("POST","/crm/cars",token,{"client_id":cA["id"],"make_model":"Toyota Camry","plate":f"A{stamp%10000:04d}77","vin":"","category":"2"})
oA=req("POST","/crm/orders",token,{"client_id":cA["id"],"car_id":carA["id"],"status":"Мойка","items":[
    {"name":"Комплексная мойка","price":2500,"workshop":"Мойка"},
    {"name":"Химчистка ковриков","price":800,"workshop":"Мойка"},
]})
# Scenario B: chem + polish path
phoneB=f"902{(stamp+1)%10000000:07d}"
cB=req("POST","/crm/clients",token,{"name":f"Сценарий Хим {stamp%10000}","phone":phoneB,"is_vip":True})
carB=req("POST","/crm/cars",token,{"client_id":cB["id"],"make_model":"BMW X5","plate":f"B{stamp%10000:04d}77","vin":"","category":"3"})
oB=req("POST","/crm/orders",token,{"client_id":cB["id"],"car_id":carB["id"],"status":"Химчистка","items":[
    {"name":"Химчистка салона","price":12000,"workshop":"Химчистка"},
    {"name":"Полировка кузова","price":18000,"workshop":"Полировка"},
]})
# pay partial on A
req("POST","/cash/payments",token,{"order_id":oA["id"],"amount":1500,"method":"Наличные"})
# mark first item done on B
req("PATCH",f"/crm/orders/{oB['id']}/items/{oB['items'][0]['id']}",token,{"is_done":True})
print(json.dumps({"A":{"order":oA["id"],"client":cA["name"],"phone":phoneA},"B":{"order":oB["id"],"client":cB["name"],"phone":phoneB},"shift":cur["id"]},ensure_ascii=False))
