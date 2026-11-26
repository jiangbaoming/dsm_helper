import 'dart:async';

import 'package:draggable_scrollbar/draggable_scrollbar.dart';
import 'package:dsm_helper/util/function.dart';
import 'package:dsm_helper/widgets/bubble_tab_indicator.dart';
import 'package:dsm_helper/widgets/label.dart';
import 'package:dsm_helper/widgets/neu_back_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:neumorphic/neumorphic.dart';

class ContainerDetail extends StatefulWidget {
  final String name;
  ContainerDetail(this.name);
  @override
  _ContainerDetailState createState() => _ContainerDetailState();
}

class _ContainerDetailState extends State<ContainerDetail> with SingleTickerProviderStateMixin {
  TabController _tabController;
  ScrollController _scrollController = ScrollController();
  bool loading = true;
  bool hasError = false;
  String errorMsg = "";
  Timer _logTimer;
  List ports = [];
  List networks = [];
  List links = [];
  List envs = [];
  String cmd = "";
  List volumes = [];
  int memory = 0;
  double memoryPercent = 0;
  int cpuPriority = 0;
  String status = "";
  int upTime = 0;
  Map shortcut;
  List logDates = [];
  List logs = [];
  String selectedDate = "";
  List processes = [];
  @override
  void initState() {
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTab);
    getData();
    super.initState();
  }

  List _asList(dynamic v) => v is List ? v : [];
  Map _asMap(dynamic v) => v is Map ? v : {};
  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  double _asNum(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  String _str(dynamic v) => v == null ? "" : v.toString();

  getData() async {
    setState(() {
      loading = true;
      hasError = false;
    });
    try {
      var res = await Api.dockerDetail(widget.name, "get");
      if (res != null && res['success'] == true && res['data'] is Map) {
        var data = res['data'] as Map;
        var profile = data['profile'];
        var details = data['details'];
        var config = _asMap(data['Config']);
        if (profile is Map) {
          // 旧版结构：profile + details
          ports = _asList(profile['port_bindings']);
          networks = _asList(profile['network']);
          volumes = _asList(profile['volume_bindings']);
          envs = _asList(profile['env_variables']);
          memory = _asInt(profile['memory_limit']);
          shortcut = profile['shortcut'] is Map ? profile['shortcut'] : null;
          cpuPriority = _asInt(profile['cpu_priority']);
          links = _asList(profile['links']);
          if (details is Map) {
            memoryPercent = _asNum(details['memoryPercent']);
            upTime = _asInt(details['up_time']);
            status = _str(details['status']);
            cmd = _str(details['exe_cmd']);
          }
        } else {
          // 新版(Container Manager)：docker inspect 结构
          var host = _asMap(data['HostConfig']);
          var state = _asMap(data['State']);
          var net = _asMap(data['NetworkSettings']);
          shortcut = null;
          ports = [];
          var p = net['Ports'];
          if (p is Map) {
            p.forEach((k, v) {
              var key = _str(k);
              var tp = key.contains('/') ? key.split('/')[1] : '';
              var cp = key.contains('/') ? key.split('/')[0] : key;
              if (v is List && v.isNotEmpty) {
                for (var b in v) {
                  ports.add({"host_port": _str(b is Map ? b['HostPort'] : ''), "container_port": cp, "type": tp});
                }
              } else {
                ports.add({"host_port": "", "container_port": cp, "type": tp});
              }
            });
          }
          volumes = [];
          var mounts = data['Mounts'];
          if (mounts is List) {
            for (var m in mounts) {
              var mm = _asMap(m);
              volumes.add({"host_volume_file": _str(mm['Source'] ?? mm['Name']), "mount_point": _str(mm['Destination']), "type": _str(mm['Type'])});
            }
          }
          envs = [];
          var env = config['Env'];
          if (env is List) {
            for (var e in env) {
              var s = _str(e);
              var i = s.indexOf('=');
              envs.add({"key": i >= 0 ? s.substring(0, i) : s, "value": i >= 0 ? s.substring(i + 1) : ""});
            }
          }
          var cmdv = config['Cmd'] ?? config['Entrypoint'];
          cmd = cmdv is List ? cmdv.join(' ') : _str(cmdv);
          memory = _asInt(host['Memory']);
          cpuPriority = _asInt(host['CpuShares']);
          links = _asList(host['Links']);
          networks = [];
          var nets = net['Networks'];
          if (nets is Map) {
            nets.forEach((k, v) {
              networks.add({"name": _str(k), "driver": _str(_asMap(v)['Driver'])});
            });
          }
          status = _str(state['Status']);
          var started = state['StartedAt'];
          if (started is String && started.isNotEmpty && !started.startsWith("0001")) {
            try {
              upTime = DateTime.parse(started).millisecondsSinceEpoch ~/ 1000;
            } catch (_) {}
          }
          // 兜底：若 inspect 信息缺失，退回 details
          if (details is Map) {
            if (status.isEmpty) status = _str(details['status']);
            if (upTime == 0) upTime = _asInt(details['up_time']);
            if (cmd.isEmpty) cmd = _str(details['exe_cmd']);
            if (memoryPercent == 0) memoryPercent = _asNum(details['memoryPercent']);
          }
        }
        setState(() {
          loading = false;
        });
      } else {
        setState(() {
          loading = false;
          hasError = true;
          errorMsg = "获取详情失败";
        });
      }
      // 进程信息（尽力而为，失败不影响主页面）
      try {
        var process = await Api.dockerDetail(widget.name, "get_process");
        if (process != null && process['success'] == true && _asMap(process['data'])['processes'] is List) {
          setState(() {
            processes = process['data']['processes'];
          });
        }
      } catch (_) {}
      getLogs();
    } catch (e) {
      setState(() {
        loading = false;
        hasError = true;
        errorMsg = e.toString();
      });
    }
  }

  void _onTab() {
    if (_tabController.index == 2) {
      getLogs();
      _startLogTimer();
    } else {
      _stopLogTimer();
    }
  }

  void _startLogTimer() {
    _stopLogTimer();
    _logTimer = Timer.periodic(Duration(seconds: 5), (_) => getLogs());
  }

  void _stopLogTimer() {
    if (_logTimer != null) {
      _logTimer.cancel();
      _logTimer = null;
    }
  }

  Future<void> getLogs() async {
    try {
      var res = await Api.dockerLogAll(widget.name);
      if (res != null && res['success'] == true && _asMap(res['data'])['logs'] is List) {
        List list = List.from(res['data']['logs']);
        list.sort((a, b) {
          var da = DateTime.tryParse(_str(a['created']));
          var db = DateTime.tryParse(_str(b['created']));
          if (da == null || db == null) return 0;
          return db.compareTo(da);
        });
        if (!mounted) return;
        setState(() {
          logs = list;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _stopLogTimer();
    _tabController.removeListener(_onTab);
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildPortItem(port) {
    return Padding(
      padding: EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "${port['host_port']}",
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              "${port['container_port']}",
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              "${port['type']}",
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVolumeItem(volume) {
    return Padding(
      padding: EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              "${volume['host_volume_file']}",
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              "${volume['mount_point']}",
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              "${volume['type']}",
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkItem(link) {
    return Padding(
      padding: EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "${link['link_container']}",
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              "${link['alias']}",
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkItem(network) {
    return Padding(
      padding: EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "${network['name']}",
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              "${network['driver']}",
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnvItem(env) {
    return Padding(
      padding: EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Text(
            "${env['key']}：",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Text(
              "${env['value']}",
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessItem(process) {
    return NeuCard(
      width: double.infinity,
      decoration: NeumorphicDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      margin: EdgeInsets.symmetric(horizontal: 20),
      curveType: CurveType.flat,
      bevel: 10,
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "进程：${process['pid']}",
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    "CPU：${process['cpu']}%",
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    "RAM：${Util.formatSize(process['memory'], fixed: 0)}",
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 5,
            ),
            Text(process['command']),
          ],
        ),
      ),
    );
  }

  String _fmt2(int n) => n < 10 ? "0" + n.toString() : n.toString();

  String _logTime(dynamic created) {
    if (created == null) return "";
    var s = created.toString().trim();
    try {
      // 数字时间戳：兼容秒/毫秒
      var asInt = int.tryParse(s);
      if (asInt != null) {
        var ms = asInt > 100000000000 ? asInt : asInt * 1000;
        var d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
        return _fmt2(d.hour) + ":" + _fmt2(d.minute) + ":" + _fmt2(d.second);
      }
      // ISO 字符串：带 Z 或 ±偏移的会解析成 UTC/带偏移，统一转本地时区再取时分秒
      var dt = DateTime.parse(s).toLocal();
      return _fmt2(dt.hour) + ":" + _fmt2(dt.minute) + ":" + _fmt2(dt.second);
    } catch (_) {
      return s;
    }
  }

  Widget _buildLogItem(log) {
    var stream = (log['stream'] ?? '').toString();
    var text = (log['text'] ?? '').toString();
    var isErr = stream.isNotEmpty && stream != "stdout";
    var fg = isErr
        ? Colors.redAccent
        : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87);
    return Container(
      padding: EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _logTime(log['created']),
            style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey, height: 1.45),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.45, color: fg),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateItem(date) {
    String str = date;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedDate = date;
        });
        getLogs();
      },
      child: NeuCard(
        width: double.infinity,
        decoration: NeumorphicDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        curveType: date == selectedDate ? CurveType.emboss : CurveType.flat,
        bevel: 10,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Column(
            children: [
              Text(
                "${str.substring(5)}",
              ),
              Text(
                "${str.substring(0, 4)}",
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(context),
        title: Text(widget.name),
      ),
      body: (loading || hasError)
          ? Center(
              child: hasError
                  ? NeuCard(
                      padding: EdgeInsets.all(40),
                      curveType: CurveType.flat,
                      decoration: NeumorphicDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      bevel: 20,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("加载失败", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          SizedBox(height: 8),
                          Text(errorMsg, style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
                          SizedBox(height: 12),
                          NeuButton(
                            onPressed: getData,
                            decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            bevel: 5,
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Text("重试", textAlign: TextAlign.center),
                          ),
                        ],
                      ),
                    )
                  : NeuCard(
                      padding: EdgeInsets.all(50),
                      curveType: CurveType.flat,
                      decoration: NeumorphicDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      bevel: 20,
                      child: CupertinoActivityIndicator(
                        radius: 14,
                      ),
                    ),
            )
          : Column(
              children: [
                NeuCard(
                  width: double.infinity,
                  decoration: NeumorphicDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  margin: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                  curveType: CurveType.flat,
                  bevel: 10,
                  child: TabBar(
                    isScrollable: false,
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                    unselectedLabelColor: Colors.grey,
                    indicator: BubbleTabIndicator(
                      indicatorColor: Theme.of(context).scaffoldBackgroundColor,
                      shadowColor: Util.getAdjustColor(Theme.of(context).scaffoldBackgroundColor, -20),
                    ),
                    tabs: [
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                        child: Text("总览"),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                        child: Text("进程"),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                        child: Text("日志"),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      ListView(
                        children: [
                          NeuCard(
                            margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            curveType: CurveType.flat,
                            bevel: 20,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "基本信息",
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(
                                    height: 5,
                                  ),
                                  Row(
                                    children: [
                                      Text("启动时间："),
                                      Expanded(
                                        child: Text(
                                          upTime > 0 ? DateTime.fromMillisecondsSinceEpoch(upTime * 1000).timeAgo : "—",
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    height: 5,
                                  ),
                                  Row(
                                    children: [
                                      Text("快捷方式："),
                                      Expanded(
                                        child: Text(
                                          shortcut == null
                                              ? "无"
                                              : (shortcut['enable_shortcut'] == true
                                                  ? (shortcut['enable_status_page'] == true
                                                      ? "状态页面"
                                                      : shortcut['enable_web_page'] == true
                                                          ? _str(shortcut['web_page_url'])
                                                          : "")
                                                  : "无"),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    height: 5,
                                  ),
                                  Row(
                                    children: [
                                      Text("CPU优先顺序："),
                                      Expanded(
                                        child: Text(
                                          cpuPriority > 50
                                              ? "高"
                                              : cpuPriority == 50
                                                  ? "中"
                                                  : cpuPriority < 50
                                                      ? "低"
                                                      : "",
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    height: 5,
                                  ),
                                  Row(
                                    children: [
                                      Text("内存限制："),
                                      Expanded(
                                        child: Text(
                                          memory > 0 ? Util.formatSize(memory) : "自动",
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    height: 5,
                                  ),
                                  Row(
                                    children: [
                                      Text("执行命令："),
                                      Expanded(
                                        child: Text(
                                          cmd,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          NeuCard(
                            margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            curveType: CurveType.flat,
                            bevel: 20,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "端口设置",
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(
                                    height: 5,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          "本地端口",
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          "容器端口",
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          "类型",
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                  ...ports.map(_buildPortItem).toList(),
                                ],
                              ),
                            ),
                          ),
                          NeuCard(
                            margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            curveType: CurveType.flat,
                            bevel: 20,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "卷",
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(
                                    height: 5,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          "文件/文件夹",
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          "装载路径",
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          "类型",
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                  ...volumes.map(_buildVolumeItem).toList(),
                                ],
                              ),
                            ),
                          ),
                          NeuCard(
                            margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            curveType: CurveType.flat,
                            bevel: 20,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "链接",
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(
                                    height: 5,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          "容器名称",
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          "别名",
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                  ...links.map(_buildLinkItem).toList(),
                                ],
                              ),
                            ),
                          ),
                          NeuCard(
                            margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            curveType: CurveType.flat,
                            bevel: 20,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "网络",
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(
                                    height: 5,
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          "网络名称",
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          "驱动程序",
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                  ...networks.map(_buildNetworkItem).toList(),
                                ],
                              ),
                            ),
                          ),
                          NeuCard(
                            margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            curveType: CurveType.flat,
                            bevel: 20,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "环境变量",
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                  ),
                                  ...envs.map(_buildEnvItem).toList(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      processes.isEmpty
                          ? Center(
                              child: Text("暂无进程信息", style: TextStyle(color: Colors.grey)),
                            )
                          : ListView.separated(
                              itemBuilder: (context, i) {
                                return _buildProcessItem(processes[i]);
                              },
                              separatorBuilder: (context, i) {
                                return SizedBox(
                                  height: 20,
                                );
                              },
                              itemCount: processes.length),
                      logs.isEmpty
                          ? Center(
                              child: Text("暂无日志", style: TextStyle(color: Colors.grey)),
                            )
                          : Padding(
                              padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: NeuCard(
                                width: double.infinity,
                                decoration: NeumorphicDecoration(
                                  color: Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                curveType: CurveType.flat,
                                bevel: 12,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  child: DraggableScrollbar.semicircle(
                                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                                    scrollbarTimeToFade: Duration(seconds: 1),
                                    controller: _scrollController,
                                    child: ListView.builder(
                                      controller: _scrollController,
                                      padding: EdgeInsets.symmetric(vertical: 2),
                                      itemBuilder: (context, i) {
                                        return _buildLogItem(logs[i]);
                                      },
                                      itemCount: logs.length,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
