import json
import requests
import time
import base64

# 从配置文件读取配置
with open('v2raya_auth.json', 'r', encoding='utf-8') as f:
    config = json.load(f)

HOST = config.get('host', 'http://192.168.31.120:2017')
USERNAME = config.get('username', 'admin')
PASSWORD = config.get('password', 'password')
TOKEN = ""

# 登录函数
def login():
    global TOKEN
    url = f"{HOST}/api/login"
    payload = {"username": USERNAME, "password": PASSWORD}
    headers = {"content-type": "application/json"}
    response = requests.post(url, json=payload, headers=headers)
    TOKEN = response.json()["data"]["token"]
    print("登录成功")

# 获取服务状态，包含订阅信息
def get_status():
    url = f"{HOST}/api/touch"
    response = requests.get(url, headers={"Authorization": TOKEN})
    return response.json()

# 获取节点配置信息
def get_node_config(sub_id, node_id):
    # 这里需要根据API文档获取节点配置信息
    # 从状态中获取节点信息
    status = get_status()
    for sub in status["data"]["touch"]["subscriptions"]:
        if sub["id"] == sub_id:
            for node in sub["servers"]:
                if node["id"] == node_id:
                    return node
    return None

# 构建请求体
def bulid_request_body(node_ids, sub_num):
    '''构建请求体，用于测试节点延迟'''
    sub_id = int(sub_num) - 1
    _nodes = []
    for i in node_ids:
        _nodes.append({"id": i, "_type": "subscriptionServer", "sub": sub_id})
    # 转换为JSON字符串
    return json.dumps(_nodes).replace("'", '"')


# 生成v2ray订阅链接
def generate_v2ray_sub_link(node_config):
    # 从节点配置生成v2ray配置
    if not node_config:
        return "生成订阅链接失败: 节点配置为空"
    
    # 解析地址和端口
    address = node_config.get('address', '')
    add = '未知'
    port = '未知'
    if ':' in address:
        parts = address.split(':')
        add = ':'.join(parts[:-1])
        port = parts[-1]
    
    # 构建v2ray配置，按照示例格式排序
    # 提取纯协议名称，去除可能的vmess前缀
    net_value = node_config.get('net', 'tcp')
    if '(' in net_value and ')' in net_value:
        # 提取括号内的协议名称
        net_value = net_value.split('(')[1].split(')')[0]
    
    v2ray_config = {
        "ps": node_config.get('name', '未知节点'),
        "add": add,
        "port": port,
        "id": node_config.get('id', ''),
        "aid": node_config.get('aid', '0'),
        "scy": node_config.get('scy', 'auto'),
        "net": net_value,
        "type": node_config.get('type', 'none'),
        "host": node_config.get('host', ''),
        "path": node_config.get('path', ''),
        "tls": node_config.get('tls', 'none'),
        "allowInsecure": False,
        "quicSecurity": "",
        "v": "2",
        "protocol": "vmess"
    }
    
    # 转换为vmess链接格式
    vmess_str = json.dumps(v2ray_config, ensure_ascii=False)
    vmess_b64 = base64.b64encode(vmess_str.encode('utf-8')).decode('utf-8')
    vmess_link = f"vmess://{vmess_b64}"
    
    return vmess_link

# 主函数
def main():
    # 登录
    login()
    
    # 获取服务状态
    status = get_status()
    
    # 获取所有订阅
    subscriptions = status["data"]["touch"]["subscriptions"]
    print(f"发现 {len(subscriptions)} 个订阅")
    
    # 获取已连接的服务器
    connected_servers = status["data"]["touch"]["connectedServer"]
    print(f"发现 {len(connected_servers)} 个已连接的服务器")
    
    # 只处理已连接的代理
    if connected_servers:
        print(f"开始处理 {len(connected_servers)} 个已连接的代理")
        
        # 按订阅分组
        subscriptions_dict = {}
        for sub in subscriptions:
            subscriptions_dict[sub["id"]] = sub
        
        # 统计每个订阅下的已连接代理数量
        sub_proxy_count = {}
        for connect in connected_servers:
            sub_id = connect["sub"] + 1
            if sub_id not in sub_proxy_count:
                sub_proxy_count[sub_id] = 0
            sub_proxy_count[sub_id] += 1
        

        
        # 生成最终的订阅文件
        output_file = "proxy_subscriptions.txt"
        
        # 读取现有文件内容（如果存在）
        existing_links = []
        try:
            with open(output_file, "r", encoding="utf-8") as f:
                lines = f.readlines()
                # 跳过头部信息，只保留链接
                for line in lines:
                    line = line.strip()
                    if line and line.startswith("vmess://"):
                        existing_links.append(line)
        except FileNotFoundError:
            pass
        
        # 清空文件并写入头部信息
        with open(output_file, "w", encoding="utf-8") as f:
            f.write(f"# 代理订阅链接 - 生成时间: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime())}\n")
            f.write(f"# 保留最新的500个\n\n")
        
        # 处理每个已连接的代理
        new_links = []
        for i, connect in enumerate(connected_servers):
            # 提取连接信息
            node_id = connect["id"]
            sub_id = connect["sub"] + 1  # 转换为订阅ID
            
            # 查找对应的订阅
            sub_info = subscriptions_dict.get(sub_id)
            
            if sub_info:
                sub_name = sub_info.get("remarks", f"订阅 ID: {sub_id}")
                
                # 计算该订阅下的当前进度
                current_sub_proxy = 0
                for j in range(i):
                    if connected_servers[j]["sub"] + 1 == sub_id:
                        current_sub_proxy += 1
                current_sub_proxy += 1
                total_sub_proxy = sub_proxy_count.get(sub_id, 0)
                
                print(f"处理代理 {i+1}/{len(connected_servers)} - 订阅: {sub_name} ({current_sub_proxy}/{total_sub_proxy})")
                
                # 获取节点配置信息
                node_config = get_node_config(sub_id, node_id)
                if node_config:
                    # 生成v2ray订阅链接
                    share_link = generate_v2ray_sub_link(node_config)
                    new_links.append(share_link)
                    print(f"  添加代理: {node_config.get('name', '未知')}")
                    
                    # 立即写入到文件
                    with open(output_file, "a", encoding="utf-8") as f:
                        f.write(f"{share_link}\n")
        
        # 合并现有链接和新链接，去重并保留最新的500个
        all_links = list(set(new_links + existing_links))
        # 保留最新的500个（这里假设新链接是最新的）
        all_links = new_links + [link for link in existing_links if link not in new_links]
        if len(all_links) > 500:
            all_links = all_links[:500]
        
        # 重新写入文件，只保留最新的500个
        with open(output_file, "w", encoding="utf-8") as f:
            f.write(f"# 代理订阅链接 - 生成时间: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime())}\n")
            f.write(f"# 共 {len(all_links)} 个代理节点\n")
            f.write(f"# 保留最新的500个\n\n")
            for link in all_links:
                f.write(f"{link}\n")
        
        print(f"\n代理订阅链接已写入到 {output_file}")
        print(f"共生成 {len(new_links)} 个新的订阅链接")
        print(f"文件中共有 {len(all_links)} 个订阅链接")
    else:
        print("没有发现已连接的代理")

if __name__ == "__main__":
    main()
