import asyncio
import aiohttp
from aiohttp_socks import ProxyConnector
import websockets

# WebSocket 服务器地址
ROUTER_WS_URL = ""

# 代理地址
PROXY_URL = ""  # 替换为你的代理地址


async def test_connection(index: int, proxy_connector: ProxyConnector):
    """测试单个 WebSocket 连接"""
    try:
        async with websockets.connect(ROUTER_WS_URL, connector=proxy_connector) as websocket:
            print(f"连接 {index} 成功")
            await asyncio.sleep(60)  # 模拟保持连接
    except Exception as e:
        print(f"连接 {index} 失败: {e}")


async def test_max_connections(max_connections: int):
    """测试路由器的最大 WebSocket 连接数"""
    # 创建代理连接器
    proxy_connector = ProxyConnector.from_url(PROXY_URL)

    # 创建 WebSocket 连接任务
    tasks = [
        test_connection(i, proxy_connector) for i in range(max_connections)
    ]
    await asyncio.gather(*tasks)


if __name__ == "__main__":
    max_connections = 1000  # 你希望测试的最大连接数
    asyncio.run(test_max_connections(max_connections))