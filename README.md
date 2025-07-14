# downloader
&emsp;&emsp;一个支持 HTTP/FTP 协议的智能下载脚本，具备自动断点续传、下载完成检测和日志优化功能。特别适合大文件下载和不稳定网络环境。

&emsp;&emsp;A smart download script supporting HTTP/FTP protocols, featuring automatic resume from breakpoints, download completion detection, and log optimization. Ideal for downloading large files in unstable network environments.


用法: ./downloader.sh [选项] <URL>
选项:
  -d, --directory <目录>   指定下载目录 (默认: downloads)
  -i, --interval <秒>      指定检查间隔 (默认: 600秒)
  -t, --tolerance <百分比> 指定文件大小误差容忍度 (默认: 5%)
  -l, --log <文件>        指定日志文件 (默认: download.log)
  -v, --verbose           启用详细输出
  -b, --buffer <大小>     设置输出缓冲区大小 (默认: 8192字节)
  -h, --help              显示此帮助信息

示例

# 基本用法
./downloader.sh URL

# 指定下载目录
./downloader.sh -d mydownloads URL

# 自定义检查间隔(300秒)
./downloader.sh -i 300 URL

# 所有选项组合使用
./downloader.sh -d mydata -i 300 -t 2 -v URL
