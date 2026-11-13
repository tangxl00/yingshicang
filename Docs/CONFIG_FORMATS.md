# 配置源格式兼容矩阵（build 25）

调研日期 2026-11-13。证据两条腿：**① APK 内证据**、**② 生态真实采样**。
所有「真实样例」均为本轮实际抓取的 URL 或落盘 fixture，没有一条来自推理。

## 一、APK 内证据（`TwimbvPWNowimGx1hufcmdFNnBh` 重下的原版 APK）

| 发现 | 位置 | 说明 |
|---|---|---|
| Java 层不可读 | `classes.dex` 仅存桩类；`assets/libjiagu_a64.so`、`libjiagu_x64.so`、`.jgapp` 在场 | 360 加固确认，按要求不硬啃 |
| JSON5 解析器随包内置 | `assets/js/lib/json5.js`（58,694 B） | 说明配置/插件侧接受 JSON5 语法 |
| `JSON5.parse` 真实调用 | `assets/js/lib/模板.js`、`assets/js/lib/drpy2.js` | 用于播放器 conf 与规则解析 |
| base64 解码器 | `assets/js/lib/模板.js`（`base64Decode`） | 与 `**` 包装配置的解码链一致 |
| gzip 解压 | `assets/js/lib/pako.min.js` | 传输层压缩由 OkHttp 透明处理，未见配置级 gzip |
| GBK 映射表 | `assets/js/lib/gbk.js` | 印证 GBK/GB18030 回落需求 |
| AES 工具链 | `assets/js/lib/crypto-js.js`、`jsencrypt.js`、`node-rsa.js` | 加密配置存在，算法为 AES/JS 侧 |
| `var config = {…}` 形态 | `assets/js/lib/drpy.min.js`（`eval(html.match(/var config = {[\s\S]*?}/)[0]+"")`） | **JS 赋值形态只在规则/插件侧成立**，配置源本身未出现 |
| 字符串表无线索 | `resources.arsc` 解出 17,164 条字符串，`密码/口令/密钥/加密/2423/base64` 全部 0 命中 | 壳内没有口令型交互文案；口令弹窗不成立 |

结论：APK 侧只能证明「JSON5 + base64 + AES/GBK 这条技术栈存在」，无法证明具体配置形态 → 形态取舍全部交给生态采样。

## 二、真实格式矩阵

| # | 格式 | 证据来源 | 真实样例（本轮实际抓取） | 本轮结论 |
|---|---|---|---|---|
| 1 | 严格 JSON 单仓 | 生态采样 | `https://ys.cxkjg.cn/api/provide/tvbox`（2,015 B，严格 JSON，12 sites） | build 24 已支持，不回退 |
| 2 | `//` 行注释 | 生态采样 | `https://raw.liucn.cc/box/m.json`（57,874 B，234 sites）；`a736240087/tvbox/main/1.json` 开头 3 行注释 | build 24 已支持 |
| 3 | `/* */` 块注释 | 生态采样 | `https://raw.githubusercontent.com/qist/tvbox/master/9918.json`（14,844 B） | build 24 已支持 |
| 4 | 尾逗号 | 生态采样 | `https://clun.top/box.json`（31,412 B，101 sites）、`cspoh123/tvbox/main/tvbox.json` | build 24 已支持 |
| 5 | UTF-8 BOM | 生态采样 | `https://szyyds.cn/tv/x.json`（30,571 B，62 sites） | build 24 已支持 |
| 6 | GBK/GB18030 回落 | APK `js/lib/gbk.js` + build 24 用例 | `BodyDecoder` 回落路径 | build 24 已支持 |
| 7 | 多仓索引 `{"urls":[{"url","name"}]}` | 生态采样 | `http://ztha.top/TVBox/GYCK.json`（3,532 B，32 仓）、`noimank/tvbox/main/tvboxmuti.json`（1,966 B，14 仓）、`ofind.cn/juhe-subhub/merged*.json` | build 24 已支持 |
| 8 | 多仓索引纯字符串数组 `{"urls":["…"]}` | 生态采样（FongMi `Depot.java` 字段为 `url`+`name`） | 无独立真实样本命中（存量变体已由 `storeFromDictionary` 覆盖） | build 24 已支持 |
| 9 | 多仓索引 `lines[]` 嵌套 | FongMi `Depot.java` 只声明 `url`/`name`；全网采样 `lines`/`storeHouse` **0 命中** | **未发现真实样本** | 保留 build 24 已有解析（不新增、不宣称支持） |
| 10 | 多仓索引放在 `.txt` 后缀 | 生态采样 | `http://xmbjm.fh4u.org/dc.txt`（6,075 B，`{"urls":[…]}` + 尾部 HTML 尾巴） | build 24 已支持（按内容而非后缀判定） |
| 11 | base64 包装（二进制前导 + `XXXXXXXX**` + base64） | 生态采样 + FongMi `Decoder#verify`（`BASE64_PREFIX = [A-Za-z0-9]{8}\*\*`） | `http://www.饭太硬.cc/tv`（18,843 B：JPEG `ffd8ffe0` 头 2,401 B + `HnPSxaeH**` + base64，解出 12,323 B 配置，49 sites，payload 仍带 `//` 注释） | **build 25 新增** |
| 12 | AES-CBC 配置（`2423` 头部） | 生态采样 + FongMi `Decoder#cbc` | `https://www.wya6.cn/tv/yc.json`（30,444 B 十六进制，头部 `2423` + `$#wycxd#$`，实测解密成功 → 14,543 B 严格 JSON，4 sites） | **build 25 新增** |
| 13 | JS 对象字面量 / 类 JSON5（未加引号键、单引号串） | 生态采样 + APK `json5.js` | `https://raw.githubusercontent.com/gsdlj/TVBox/main/4.txt`（12,586 B，`{spider:'…',sites:[{key:'t4public',…}]}`，归一后 77 sites） | **build 25 新增** |
| 14 | 苹果CMS 采集接口直配（`type:1` + `api.php/provide/vod`） | 生态采样 | `https://ys.cxkjg.cn/api/provide/vod?ac=list`（15,746 B 采集响应）；配置侧同域 `…/api/provide/tvbox` | 不需要新解码器：真实配置把它写成**普通 JSON 站点条目**（见 #1） |
| 15 | 纯文本直播列表（`频道,#genre#` CSV） | 生态采样 | `https://raw.githubusercontent.com/qist/tvbox/master/ITV.txt`（88,216 B）、`FTY/id.txt`（9,549 B） | 维持移除：`lives` 不建模，不新增解析 |
| 16 | 配置级 gzip | 生态采样 34 份样本扫 `1f 8b` 魔数，**0 命中** | **未发现真实样本** | 不实现（传输层压缩由 URLSession 透明处理） |
| 17 | 口令型加密（密钥来自用户输入） | APK 字符串表 0 命中；FongMi `Decoder#cbc` 密钥**内嵌明文头部**；`Auth.java` 只有 HTTP Basic/Digest | **未发现真实样本** | 不实现，不做口令弹窗（无证据即不造交互） |
| 18 | jar spider（`spider` 指向 `.jar`） | 生态采样普遍存在 | `m.json` 的 `./fty.jar;md5;…` | 维持平台级不支持 |
| 19 | 腾讯广告壳 / 落地页伪装 | 生态采样 | `https://927r.top/api`（185 B 跳转脚本）、`https://api.aa1.cn/doc/tvbox.html`（180 KB 网页） | 不是配置：按 HTML 拒绝并给出真实原因 |

## 三、下轮（本轮不做，理由）

- **#9 `lines` 嵌套 / `storeHouse`**：采样 0 命中，无 fixture 就无法写真实回归用例；补做前提是先找到真实源。
- **#12 的「AES + 口令」组合**：现有证据里 AES 密钥来自明文头部，口令分支无样本。若后续出现，需新增弹窗与密钥内存管理（`Docs/CONFIG_FORMATS.md` 已记入待办）。
- **#16 配置级 gzip**：`URLSession` 自动解压 `Content-Encoding`，额外实现只会引入字节层歧义。

## 四、实现落位

| 层 | 文件 | 职责 |
|---|---|---|
| 字节流归一 | `Yingshicang/Core/Config/ConfigPayloadSupport.swift` `stripPreamble` | 去 UTF-8 BOM 字节、前导 NUL |
| 形态识别 | 同文件 `marker(in:)` | **在字节层**找 `[A-Za-z0-9]{8}**`；GB18030 回落会吞掉标记，故必须在解码前判 |
| base64 解码 | 同文件 `base64Payload` | 收集 base64 字母表字符、补 `=`、解码 |
| AES 解码 | 同文件 `aes2423Decrypt` | `2423` → hex2byte → 小写 → `$#… #$` 取 key、末 13 位取 IV、`2324` 后截末 26 位为密文、AES-CBC/PKCS7（CommonCrypto） |
| JS 字面量归一 | 同文件 `JSON5Lite.toJSON` | 单引号→双引号、裸键加引号、去尾逗号；遇反引号模板串返回明确不支持 |
| 编码判定 | 复用 `BodyDecoder` | UTF-8 优先 → GB18030 回落 |
| JSON 校验 / 剥注释 | 复用 build 24 `stripJSONNoise` / `analyze` | 不推翻原结构 |

**安全基线**：密钥只在内存里参与 `CCCrypt`，不写日志、不进错误文案；错误提示只说「缺少 `$#…#$` 密钥段」「密文长度不是 16 的整数倍」这类结构性原因，从不回显密钥本身。
