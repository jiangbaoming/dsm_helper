import 'dart:async';

import 'package:dsm_helper/pages/docker/compose_editor.dart';
import 'package:dsm_helper/pages/docker/detail.dart';
import 'package:dsm_helper/util/function.dart';
import 'package:dsm_helper/widgets/label.dart';
import 'package:dsm_helper/widgets/neu_back_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:neumorphic/neumorphic.dart';

/// 容器管理器 - 项目(compose)详情页
class ProjectDetail extends StatefulWidget {
  final Map project;
  ProjectDetail(this.project);
  @override
  _ProjectDetailState createState() => _ProjectDetailState();
}

class _ProjectDetailState extends State<ProjectDetail> {
  bool loading = true;
  bool hasError = false;
  String errorMsg = "";
  String name = "";
  String status = "";
  String path = "";
  String content = "";
  List containers = [];
  Map data = {};
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    getData();
  }

  String _s(dynamic v) => v == null ? "" : v.toString();

  String _errText(dynamic res) {
    try {
      var code = res['error']['code'];
      return code == null ? "" : ("，代码：" + code.toString());
    } catch (_) {
      return "";
    }
  }

  Future<void> getData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        hasError = false;
      });
    }
    try {
      var res = await Api.dockerProjectGet(widget.project['id']);
      if (res != null && res['success'] == true && res['data'] is Map) {
        var d = res['data'];
        data = d;
        name = _s(d['name'] ?? widget.project['name']);
        status = _s(d['status']);
        path = _s(d['path'] ?? d['share_path']);
        var c = _s(d['content']);
        if (c.isNotEmpty) content = c;
        if (d['containers'] is List) containers = d['containers'];
        if (mounted) {
          setState(() {
            if (!silent) loading = false;
          });
        }
      } else {
        if (!silent && mounted) {
          setState(() {
            loading = false;
            hasError = true;
            errorMsg = "获取项目详情失败" + _errText(res);
          });
        }
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() {
          loading = false;
          hasError = true;
          errorMsg = e.toString();
        });
      }
    }
  }

  /// 执行项目动作，并在之后轮询项目状态直到到达 expected（或超时）
  Future<void> _runAction(String action, String label, String expected) async {
    if (_actionLoading) return;
    setState(() {
      _actionLoading = true;
    });
    try {
      var res = await Api.dockerProjectAction(widget.project['id'], action);
      // 普通方法返回 JSON（Map）；若返回非 Map 视为已提交，交给状态轮询判断
      if (res is Map && res['success'] == false) {
        Util.toast(label + "失败" + _errText(res));
      } else {
        Util.toast(label + "已提交");
        for (int i = 0; i < 45; i++) {
          await Future.delayed(Duration(seconds: 2));
          if (!mounted) break;
          await getData(silent: true);
          if (status == expected) break;
        }
        if (mounted) await getData(silent: true);
      }
    } catch (e) {
      Util.toast(label + "异常：" + e.toString());
    }
    if (mounted) {
      setState(() {
        _actionLoading = false;
      });
    }
  }

  Future<void> doBuild() => _runAction("build", "构建", "STOPPED");
  Future<void> doStart() => _runAction("start", "启动", "RUNNING");
  Future<void> doStop() => _runAction("stop", "停止", "STOPPED");
  // 清除 = docker-compose down：停止并移除项目创建的容器/网络，保留项目与镜像
  Future<void> doClean() => _runAction("clean", "清除", "STOPPED");

  Future<void> doDelete() async {
    if (_actionLoading) return;
    setState(() {
      _actionLoading = true;
    });
    try {
      var res = await Api.dockerProjectAction(widget.project['id'], "delete");
      if (res is Map && res['success'] == false) {
        Util.toast("删除失败" + _errText(res));
        if (mounted) setState(() { _actionLoading = false; });
      } else {
        Util.toast("已删除");
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      Util.toast("删除异常：" + e.toString());
      if (mounted) setState(() { _actionLoading = false; });
    }
  }

  Future<void> containerAction(String cname, String action) async {
    try {
      var res = await Api.dockerPower(cname, action);
      if (res != null && res['success'] == true) {
        Util.toast("请求发送成功");
        getData();
      } else {
        var code;
        try {
          code = res['error']['code'];
        } catch (_) {}
        Util.toast("请求失败" + (code == null ? "" : "，代码：" + code.toString()));
      }
    } catch (e) {
      Util.toast("请求异常：" + e.toString());
    }
  }

  Future<void> _confirmClear() async {
    bool ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("清除项目"),
        content: Text("确定清除项目 " + name + " 吗？\n将停止并移除该项目创建的容器/网络（项目与镜像保留，可再次构建）。"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("取消")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("确定", style: TextStyle(color: Colors.deepOrange))),
        ],
      ),
    );
    if (ok == true) doClean();
  }

  Future<void> _confirmDelete() async {
    bool ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("删除项目"),
        content: Text("确定删除项目 " + name + " 吗？\n将删除该项目的所有容器和数据（不可恢复）。"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("取消")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("删除", style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok == true) doDelete();
  }

  Widget _miniAction(String text, Color color, VoidCallback onPressed, {bool enabled = true}) {
    return NeuButton(
      onPressed: enabled ? onPressed : null,
      decoration: NeumorphicDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(25)),
      bevel: 5,
      padding: EdgeInsets.symmetric(horizontal: 2, vertical: 10),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: enabled ? color : Colors.grey)),
    );
  }

  Color _statusColor(String s) {
    if (s == "RUNNING") return Colors.green;
    if (s == "STOPPED") return Colors.red;
    return Colors.orange;
  }

  String _statusText(String s) {
    switch (s) {
      case "RUNNING":
        return "运行中";
      case "STOPPED":
        return "已停止";
      case "STARTING":
        return "启动中";
      case "STOPPING":
        return "停止中";
      case "BUILDING":
        return "构建中";
      case "RESTARTING":
        return "重启中";
      case "CLEANING":
        return "清除中";
      case "DELETING":
        return "删除中";
      case "UPDATING":
        return "更新中";
      default:
        return s.isEmpty ? "未知" : s;
    }
  }

  bool get _running => status == "RUNNING";
  bool get _busyStatus => ["BUILDING", "STARTING", "STOPPING", "RESTARTING", "CLEANING", "DELETING", "UPDATING"].contains(status);
  bool get _tappable => !_actionLoading && !_busyStatus;
  // 构建/清除/删除：仅“已停止/未知/错误”且无进行中操作时可用
  bool get _canManage => !_running && _tappable;
  bool get _canStart => (status == "STOPPED" || status == "ERROR" || status.isEmpty) && _tappable;
  bool get _canStop => _running && _tappable;

  Widget _card(List<Widget> children) {
    return NeuCard(
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
          children: children,
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Widget _actionBtn(String text, Color color, VoidCallback onPressed) {
    return Expanded(
      child: NeuButton(
        onPressed: onPressed,
        decoration: NeumorphicDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(25),
        ),
        bevel: 5,
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: color),
        ),
      ),
    );
  }

  Widget _buildContainerItem(c) {
    var cfg = (c['Config'] is Map) ? c['Config'] : {};
    var st = (c['State'] is Map) ? c['State'] : {};
    var cn = _s(c['Name']);
    if (cn.startsWith('/')) cn = cn.substring(1);
    var cs = _s(st['Status']);
    var running = cs == "running";
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(CupertinoPageRoute(builder: (context) => ContainerDetail(cn)));
      },
      child: Container(
        margin: EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cn, style: TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  SizedBox(height: 2),
                  Text(_s(cfg['Image']), style: TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            SizedBox(width: 10),
            Label(cs, running ? Colors.green : Colors.red),
            SizedBox(width: 8),
            GestureDetector(
              onTap: () => containerAction(cn, running ? "stop" : "start"),
              child: Icon(running ? Icons.stop_circle_outlined : Icons.play_circle_outline, color: running ? Colors.redAccent : Colors.green, size: 26),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(context),
        title: Text(name.isEmpty ? _s(widget.project['name']) : name),
      ),
      body: loading
          ? Center(
              child: NeuCard(
                padding: EdgeInsets.all(50),
                curveType: CurveType.flat,
                decoration: NeumorphicDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                bevel: 20,
                child: CupertinoActivityIndicator(radius: 14),
              ),
            )
          : (hasError
              ? Center(
                  child: _card([
                    Text("加载失败", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    SizedBox(height: 8),
                    Text(errorMsg, style: TextStyle(color: Colors.grey)),
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
                  ]),
                )
              : ListView(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  children: [
                    _card([
                      Text("基本信息", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      SizedBox(height: 5),
                      _kv("名称：", name),
                      _kv("状态：", _statusText(status)),
                      _kv("路径：", path),
                    ]),
                    _card([
                      if (_actionLoading || _busyStatus)
                        Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              SizedBox(width: 16, height: 16, child: CupertinoActivityIndicator(radius: 8)),
                              SizedBox(width: 10),
                              Text(_actionLoading ? "处理中，请稍候…" : ("状态：" + _statusText(status)), style: TextStyle(color: Colors.grey, fontSize: 13)),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(child: _miniAction("构建", Colors.blue, () => doBuild(), enabled: _canManage)),
                          SizedBox(width: 6),
                          Expanded(child: _miniAction("启动", Colors.green, () => doStart(), enabled: _canStart)),
                          SizedBox(width: 6),
                          Expanded(child: _miniAction("停止", Colors.orange, () => doStop(), enabled: _canStop)),
                          SizedBox(width: 6),
                          Expanded(child: _miniAction("清除", Colors.deepOrange, () => _confirmClear(), enabled: _canManage)),
                          SizedBox(width: 6),
                          Expanded(child: _miniAction("删除", Colors.redAccent, () => _confirmDelete(), enabled: _canManage)),
                        ],
                      ),
                    ]),
                    _card([
                      Text("容器", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      if (containers.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text("暂无容器信息", style: TextStyle(color: Colors.grey)),
                        )
                      else
                        ...containers.map(_buildContainerItem).toList(),
                    ]),
                    _card([
                      Row(
                        children: [
                          Expanded(
                            child: Text("Compose 内容", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          ),
                          NeuButton(
                            onPressed: () async {
                              var result = await Navigator.of(context).push<String>(CupertinoPageRoute(
                                builder: (context) => ComposeEditor(title: name + " - compose", content: content),
                              ));
                              if (result != null && result != content) {
                                var r = await Api.dockerProjectUpdate(widget.project['id'], result);
                                if (r != null && r['success'] == true) {
                                  Util.toast("保存成功");
                                  getData();
                                } else {
                                  Util.toast("保存失败" + _errText(r));
                                }
                              }
                            },
                            decoration: NeumorphicDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(20)),
                            bevel: 5,
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text("编辑"),
                          ),
                        ],
                      ),
                      SizedBox(height: 5),
                      if (content.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text("无法获取 compose 内容", style: TextStyle(color: Colors.grey)),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark ? Colors.black26 : Colors.black.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SelectableText(
                            content,
                            style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                    ]),
                  ],
                )),
    );
  }
}
