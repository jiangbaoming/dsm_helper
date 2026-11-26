import 'dart:async';

import 'package:dsm_helper/pages/docker/detail.dart';
import 'package:dsm_helper/pages/docker/project_detail.dart';
import 'package:dsm_helper/util/function.dart';
import 'package:dsm_helper/util/log.dart';
import 'package:dsm_helper/widgets/bubble_tab_indicator.dart';
import 'package:dsm_helper/widgets/animation_progress_bar.dart';
import 'package:dsm_helper/widgets/label.dart';
import 'package:dsm_helper/widgets/neu_back_button.dart';
import 'package:extended_text/extended_text.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:neumorphic/neumorphic.dart';

class Docker extends StatefulWidget {
  final String title;
  Docker({this.title: 'Docker'});
  @override
  _DockerState createState() => _DockerState();
}

class _DockerState extends State<Docker> with SingleTickerProviderStateMixin {
  TabController _tabController;
  List containers = [];
  List images = [];
  List registries = [];
  Map<String, bool> powerLoading = {};
  Map utilization;
  bool containerLoading = true;
  bool imageLoading = true;
  List projects = [];
  bool projectLoading = true;
  Map<String, bool> projectPowerLoading = {};
  bool registryLoading = true;
  @override
  void initState() {
    _tabController = TabController(length: 4, vsync: this);
    getContainer();
    getProjects();
    getImage();
    getRegistry();
    super.initState();
  }

  getContainer() async {
    var res = await Api.dockerContainerInfo();
    setState(() {
      containerLoading = false;
    });
    if (res['success']) {
      List result = res['data']['result'];
      result.forEach((item) {
        if (item['success'] == true) {
          switch (item['api']) {
            case "SYNO.Core.System.Utilization":
              setState(() {
                utilization = item['data'];
              });
              break;
            case "SYNO.Docker.Container":
              setState(() {
                containers = item['data']['containers'];
                containers.sort((a, b) {
                  return a['name'].compareTo(b['name']);
                });
              });
              break;
            case "SYNO.Docker.Container.Resource":
              List resources = item['data']['resources'];
              resources.forEach((resource) {
                containers.forEach((container) {
                  if (resource['name'] == container['name']) {
                    setState(() {
                      container['cpu'] = resource['cpu'];
                      container['memory'] = resource['memory'];
                      container['memoryPercent'] = resource['memoryPercent'];
                    });
                  }
                });
              });
              break;
          }
        }
      });
    }
  }

  getImage() async {
    var res = await Api.dockerImageInfo();
    Log.logger.info(res);
    setState(() {
      imageLoading = false;
    });
    if (res['success']) {
      List result = res['data']['result'];
      result.forEach((item) {
        if (item['success'] == true) {
          switch (item['api']) {
            case "SYNO.Docker.Image":
              setState(() {
                images = item['data']['images'];
                images.sort((a, b) {
                  return a['repository'].compareTo(b['repository']);
                });
              });
              break;
            case "SYNO.Docker.Registry":
              setState(() {
                registries = item['data']['registries'];
              });
              break;
          }
        }
      });
    }
  }

  getProjects() async {
    var res = await Api.dockerProjectList();
    setState(() {
      projectLoading = false;
    });
    if (res != null && res['success'] == true) {
      List list = [];
      var data = res['data'];
      if (data is Map) {
        data.forEach((k, v) {
          if (v is Map && v['id'] != null) {
            list.add(v);
          }
        });
      } else if (data is List) {
        list = data;
      }
      list.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
      setState(() {
        projects = list;
      });
    }
  }

  projectAction(project, String action) async {
    var id = project['id'];
    setState(() {
      projectPowerLoading[id] = true;
    });
    try {
      var res = await Api.dockerProjectAction(id, action);
      if (res is Map && res['success'] == false) {
        var code;
        try {
          code = res['error']['code'];
        } catch (_) {}
        Util.toast("操作失败" + (code == null ? "" : "，代码：" + code.toString()));
      } else {
        Util.toast("已提交");
        await Future.delayed(Duration(seconds: 2));
        getProjects();
      }
    } catch (e) {
      Util.toast("操作异常：" + e.toString());
    }
    if (mounted) {
      setState(() {
        projectPowerLoading[id] = false;
      });
    }
  }

  Widget _buildProjectItem(project) {
    var id = project['id'];
    var status = (project['status'] ?? '').toString();
    var services = project['services'];
    int serviceCount = services is List ? services.length : ((project['containerIds'] is List) ? project['containerIds'].length : 0);
    if (projectPowerLoading[id] == null) {
      projectPowerLoading[id] = false;
    }
    return GestureDetector(
      onTap: () {
        Navigator.of(context)
            .push(CupertinoPageRoute(
                builder: (context) {
                  return ProjectDetail(project);
                },
                settings: RouteSettings(name: "docker_project_detail")))
            .then((_) {
          getProjects();
        });
      },
      child: NeuCard(
        curveType: CurveType.flat,
        decoration: NeumorphicDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        bevel: 20,
        margin: EdgeInsets.only(bottom: 20),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (project['name'] ?? '').toString(),
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 10),
                        status == "RUNNING"
                            ? Label("运行中", Colors.green)
                            : status == "STOPPED"
                                ? Label("已停止", Colors.red)
                                : Label(status, Colors.orange),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (project['path'] ?? '').toString(),
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text("服务：" + serviceCount.toString(), style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 16),
              GestureDetector(
                onTap: () {
                  showCupertinoModalPopup(
                    context: context,
                    builder: (context) {
                      return Material(
                        color: Colors.transparent,
                        child: NeuCard(
                          width: double.infinity,
                          padding: EdgeInsets.all(22),
                          bevel: 5,
                          curveType: CurveType.emboss,
                          decoration: NeumorphicDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
                          child: SafeArea(
                            top: false,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text("选择操作", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
                                SizedBox(height: 12),
                                if (status != "RUNNING")
                                  NeuButton(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      projectAction(project, "start");
                                    },
                                    decoration: NeumorphicDecoration(
                                      color: Theme.of(context).scaffoldBackgroundColor,
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    bevel: 5,
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: Text("启动", style: TextStyle(fontSize: 18)),
                                  ),
                                if (status == "RUNNING")
                                  NeuButton(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      projectAction(project, "stop");
                                    },
                                    decoration: NeumorphicDecoration(
                                      color: Theme.of(context).scaffoldBackgroundColor,
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    bevel: 5,
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: Text("停止", style: TextStyle(fontSize: 18, color: Colors.redAccent)),
                                  ),
                                SizedBox(height: 8),
                                Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Text("构建 / 清除 / 删除请在项目详情页操作", style: TextStyle(fontSize: 12, color: Colors.grey)),
                                ),
                                SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                child: NeuCard(
                  padding: EdgeInsets.all(10),
                  decoration: NeumorphicDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  curveType: status == "RUNNING" ? CurveType.emboss : CurveType.flat,
                  bevel: 20,
                  child: projectPowerLoading[id]
                      ? CupertinoActivityIndicator()
                      : Image.asset("assets/icons/shutdown.png", width: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  power(container, String action, {bool preserveProfile}) async {
    if (action == "signal" || action == "delete") {
      showCupertinoModalPopup(
        context: context,
        builder: (context) {
          return Material(
            color: Colors.transparent,
            child: NeuCard(
              width: double.infinity,
              padding: EdgeInsets.all(22),
              bevel: 5,
              curveType: CurveType.emboss,
              decoration: NeumorphicDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      "确认操作",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                    ),
                    SizedBox(
                      height: 12,
                    ),
                    Text(
                      action == "signal"
                          ? "是否确定要强制停止容器？所有未保存的数据将丢失！"
                          : preserveProfile
                              ? "容器 ${container['name']} 将被清除。清除后，容器中的所有数据将丢失。是否确定继续？"
                              : "容器 ${container['name']} 将被删除。删除后，容器中的所有数据将丢失。是否确定继续？",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400),
                    ),
                    SizedBox(
                      height: 22,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: NeuButton(
                            onPressed: () async {
                              Navigator.of(context).pop();
                              setState(() {
                                powerLoading[container['id']] = true;
                              });
                              var res = await Api.dockerPower(container['name'], action, preserveProfile: preserveProfile);
                              if (res['success']) {
                                Util.toast("请求发送成功");
                                getContainer();
                              } else {
                                Util.toast("请求发送失败，代码：${res['error']['code']}");
                              }
                              setState(() {
                                powerLoading[container['id']] = false;
                              });
                            },
                            decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            bevel: 5,
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              "确认",
                              style: TextStyle(fontSize: 18, color: Colors.redAccent),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 16,
                        ),
                        Expanded(
                          child: NeuButton(
                            onPressed: () async {
                              Navigator.of(context).pop();
                            },
                            decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            bevel: 5,
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              "取消",
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 8,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } else {
      setState(() {
        powerLoading[container['id']] = true;
      });
      var res = await Api.dockerPower(container['name'], action);
      if (res['success']) {
        Util.toast("请求发送成功");
        getContainer();
      } else {
        Util.toast("请求发送失败，代码：${res['error']['code']}");
      }
      setState(() {
        powerLoading[container['id']] = false;
      });
    }
  }

  Widget _buildContainerItem(container) {
    if (powerLoading[container['id']] == null) {
      powerLoading[container['id']] = false;
    }
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(CupertinoPageRoute(
            builder: (context) {
              return ContainerDetail(container['name']);
            },
            settings: RouteSettings(name: "docker_container_detail")));
      },
      child: NeuCard(
        curveType: CurveType.flat,
        decoration: NeumorphicDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        bevel: 20,
        margin: EdgeInsets.only(bottom: 20),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              container['name'],
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                            Spacer(),
                            container['status'] == "running"
                                ? Label("运行中", Colors.green)
                                : container['status'] == "stopped"
                                    ? Label("已停止", Colors.red)
                                    : Label(container['status'], Colors.orange),
                          ],
                        ),
                        SizedBox(
                          height: 10,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                container['image'],
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ),
                            SizedBox(
                              width: 10,
                            ),
                            if (container['status'] == "running")
                              Text(
                                "${container['up_time']!=null ? DateTime.fromMillisecondsSinceEpoch(container['up_time'] * 1000).timeAgo : container['up_status']}",
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 20,
                  ),
                  GestureDetector(
                    onTap: () async {
                      if (powerLoading[container['id']]) {
                        return;
                      }

                      showCupertinoModalPopup(
                        context: context,
                        builder: (context) {
                          return Material(
                            color: Colors.transparent,
                            child: NeuCard(
                              width: double.infinity,
                              padding: EdgeInsets.all(22),
                              bevel: 5,
                              curveType: CurveType.emboss,
                              decoration: NeumorphicDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
                              child: SafeArea(
                                top: false,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      "选择操作",
                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                                    ),
                                    SizedBox(
                                      height: 12,
                                    ),
                                    if (container['status'] == "stopped") ...[
                                      NeuButton(
                                        onPressed: () async {
                                          Navigator.of(context).pop();
                                          power(container, "start");
                                        },
                                        decoration: NeumorphicDecoration(
                                          color: Theme.of(context).scaffoldBackgroundColor,
                                          borderRadius: BorderRadius.circular(25),
                                        ),
                                        bevel: 5,
                                        padding: EdgeInsets.symmetric(vertical: 10),
                                        child: Text(
                                          "启动",
                                          style: TextStyle(fontSize: 18),
                                        ),
                                      ),
                                      SizedBox(
                                        height: 22,
                                      ),
                                      NeuButton(
                                        onPressed: () async {
                                          Navigator.of(context).pop();
                                          power(container, "delete", preserveProfile: true);
                                        },
                                        decoration: NeumorphicDecoration(
                                          color: Theme.of(context).scaffoldBackgroundColor,
                                          borderRadius: BorderRadius.circular(25),
                                        ),
                                        bevel: 5,
                                        padding: EdgeInsets.symmetric(vertical: 10),
                                        child: Text(
                                          "清除",
                                          style: TextStyle(fontSize: 18, color: Colors.redAccent),
                                        ),
                                      ),
                                      SizedBox(
                                        height: 22,
                                      ),
                                      NeuButton(
                                        onPressed: () async {
                                          Navigator.of(context).pop();
                                          power(container, "delete", preserveProfile: false);
                                        },
                                        decoration: NeumorphicDecoration(
                                          color: Theme.of(context).scaffoldBackgroundColor,
                                          borderRadius: BorderRadius.circular(25),
                                        ),
                                        bevel: 5,
                                        padding: EdgeInsets.symmetric(vertical: 10),
                                        child: Text(
                                          "删除",
                                          style: TextStyle(fontSize: 18, color: Colors.redAccent),
                                        ),
                                      ),
                                    ] else ...[
                                      NeuButton(
                                        onPressed: () async {
                                          Navigator.of(context).pop();
                                          power(container, "stop");
                                        },
                                        decoration: NeumorphicDecoration(
                                          color: Theme.of(context).scaffoldBackgroundColor,
                                          borderRadius: BorderRadius.circular(25),
                                        ),
                                        bevel: 5,
                                        padding: EdgeInsets.symmetric(vertical: 10),
                                        child: Text(
                                          "停止",
                                          style: TextStyle(fontSize: 18, color: Colors.redAccent),
                                        ),
                                      ),
                                      SizedBox(
                                        height: 22,
                                      ),
                                      NeuButton(
                                        onPressed: () async {
                                          Navigator.of(context).pop();
                                          power(container, "signal");
                                        },
                                        decoration: NeumorphicDecoration(
                                          color: Theme.of(context).scaffoldBackgroundColor,
                                          borderRadius: BorderRadius.circular(25),
                                        ),
                                        bevel: 5,
                                        padding: EdgeInsets.symmetric(vertical: 10),
                                        child: Text(
                                          "强制停止",
                                          style: TextStyle(fontSize: 18, color: Colors.redAccent),
                                        ),
                                      ),
                                      SizedBox(
                                        height: 22,
                                      ),
                                      NeuButton(
                                        onPressed: () async {
                                          Navigator.of(context).pop();
                                          power(container, "restart");
                                        },
                                        decoration: NeumorphicDecoration(
                                          color: Theme.of(context).scaffoldBackgroundColor,
                                          borderRadius: BorderRadius.circular(25),
                                        ),
                                        bevel: 5,
                                        padding: EdgeInsets.symmetric(vertical: 10),
                                        child: Text(
                                          "重新启动",
                                          style: TextStyle(fontSize: 18, color: Colors.redAccent),
                                        ),
                                      ),
                                    ],
                                    SizedBox(
                                      height: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                    child: NeuCard(
                      padding: EdgeInsets.all(10),
                      // margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      // padding: EdgeInsets.symmetric(vertical: 20),
                      decoration: NeumorphicDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      curveType: container['status'] == "running" ? CurveType.emboss : CurveType.flat,
                      bevel: 20,
                      child: powerLoading[container['id']]
                          ? CupertinoActivityIndicator()
                          : Image.asset(
                              "assets/icons/shutdown.png",
                              width: 20,
                            ),
                    ),
                  ),
                ],
              ),
              if (container['status'] == "running") ...[
                SizedBox(
                  height: 10,
                ),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text("CPU"),
                              Spacer(),
                              Text(
                                "${container['cpu'].toStringAsFixed(2)}%",
                                style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          SizedBox(
                            height: 10,
                          ),
                          NeuCard(
                            curveType: CurveType.flat,
                            bevel: 10,
                            decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: FAProgressBar(
                              backgroundColor: Colors.transparent,
                              changeColorValue: 90,
                              changeProgressColor: Colors.red,
                              progressColor: Colors.blue,
                              size: 20,
                              displayText: "%",
                              currentValue: (container['cpu']).ceil(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 20,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text("内存"),
                              Spacer(),
                              Text(
                                "${Util.formatSize(container['memory'], fixed: 0)}",
                                style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          SizedBox(
                            height: 10,
                          ),
                          NeuCard(
                            curveType: CurveType.flat,
                            bevel: 10,
                            decoration: NeumorphicDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: FAProgressBar(
                              backgroundColor: Colors.transparent,
                              changeColorValue: 90,
                              changeProgressColor: Colors.red,
                              progressColor: Colors.green,
                              size: 20,
                              displayText: "%",
                              currentValue: container['memoryPercent'].ceil(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageItem(image) {
    return NeuCard(
      curveType: CurveType.flat,
      decoration: NeumorphicDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      bevel: 20,
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: ExtendedText(
                    "${image['repository']}:${image['tags'].join(",")}",
                    maxLines: 1,
                    overflowWidget: TextOverflowWidget(
                      position: TextOverflowPosition.middle,
                      align: TextOverflowAlign.right,
                      child: Text(
                        "…",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(
                  width: 10,
                ),
                Label(Util.formatSize(image['size'], fixed: 0, format: 1000), Theme.of(context).primaryColor),
              ],
            ),
            if (image['description'] != null || image['description'] != '') ...[
              SizedBox(
                height: 10,
              ),
              Text(
                "${image['description']}",
                style: TextStyle(
                  color: Colors.grey,
                ),
              )
            ],
          ],
        ),
      ),
    );
  }

  getRegistry() async {
    var res = await Api.dockerRegistryInfo();
    setState(() {
      registryLoading = false;
    });
    if (res != null && res['success'] == true) {
      var data = res['data'];
      List list = [];
      if (data is Map && data['registries'] is List) {
        list = List.from(data['registries']);
      }
      setState(() {
        registries = list;
      });
    }
  }

  registryAction(String action, {String name, String url, String username, String password}) async {
    Map res;
    try {
      if (action == "create") {
        res = await Api.dockerRegistryCreate(name, url, username: username, password: password);
      } else if (action == "delete") {
        res = await Api.dockerRegistryDelete(name);
      } else if (action == "using") {
        res = await Api.dockerRegistryUsing(name);
      }
    } catch (e) {
      Util.toast("操作异常：" + e.toString());
      return;
    }
    if (res != null && res['success'] == true) {
      Util.toast("操作成功");
      getRegistry();
    } else {
      var code;
      try {
        code = res['error']['code'];
      } catch (_) {}
      Util.toast("操作失败" + (code == null ? "" : "，代码：" + code.toString()));
    }
  }

  Widget _buildRegistryItem(registry) {
    var name = (registry['name'] ?? '').toString();
    var url = (registry['url'] ?? '').toString();
    var isUsing = registry['using'] == true || registry['is_using'] == true || registry['default'] == true;
    return NeuCard(
      curveType: CurveType.flat,
      decoration: NeumorphicDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      bevel: 20,
      margin: EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (isUsing) Label("默认", Colors.blue),
              ],
            ),
            SizedBox(height: 8),
            Text(url, style: TextStyle(fontSize: 12, color: Colors.grey)),
            SizedBox(height: 12),
            Row(
              children: [
                if (!isUsing) ...[
                  Expanded(
                    child: NeuButton(
                      onPressed: () => registryAction("using", name: name, url: url),
                      decoration: NeumorphicDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(25)),
                      bevel: 5,
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text("设为默认", textAlign: TextAlign.center, style: TextStyle(fontSize: 14)),
                    ),
                  ),
                  SizedBox(width: 12),
                ],
                Expanded(
                  child: NeuButton(
                    onPressed: () => registryAction("delete", name: name, url: url),
                    decoration: NeumorphicDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(25)),
                    bevel: 5,
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text("删除", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.redAccent)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddRegistry() {
    var nameCtrl = TextEditingController();
    var urlCtrl = TextEditingController();
    var userCtrl = TextEditingController();
    var passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text("添加注册表"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: InputDecoration(labelText: "名称")),
                TextField(controller: urlCtrl, decoration: InputDecoration(labelText: "地址 URL")),
                TextField(controller: userCtrl, decoration: InputDecoration(labelText: "用户名(可选)")),
                TextField(controller: passCtrl, decoration: InputDecoration(labelText: "密码(可选)"), obscureText: true),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text("取消")),
            TextButton(
              onPressed: () {
                var n = nameCtrl.text.trim();
                var u = urlCtrl.text.trim();
                if (n.isEmpty || u.isEmpty) {
                  Util.toast("名称和地址不能为空");
                  return;
                }
                Navigator.pop(ctx);
                registryAction("create", name: n, url: u, username: userCtrl.text.trim(), password: passCtrl.text.trim());
              },
              child: Text("添加"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(context),
        title: Text(widget.title),
      ),
      body: Column(
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
                  child: Text("项目"),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                  child: Text("容器"),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                  child: Text("镜像"),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                  child: Text("注册表"),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                projectLoading
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
                    : ListView(
                        padding: EdgeInsets.all(20),
                        children: [
                          if (projects.isEmpty)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text("暂无项目", style: TextStyle(color: Colors.grey)),
                              ),
                            )
                          else
                            ...projects.map(_buildProjectItem).toList(),
                        ],
                      ),
                containerLoading
                    ? Center(
                        child: NeuCard(
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
                    : ListView(
                        padding: EdgeInsets.all(20),
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: NeuCard(
                                  curveType: CurveType.flat,
                                  decoration: NeumorphicDecoration(
                                    color: Theme.of(context).scaffoldBackgroundColor,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  bevel: 20,
                                  child: Padding(
                                    padding: const EdgeInsets.all(20.0),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Image.asset(
                                              "assets/icons/cpu.png",
                                              width: 50,
                                            ),
                                            SizedBox(
                                              width: 10,
                                            ),
                                            Text(
                                              "CPU",
                                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                        SizedBox(
                                          height: 10,
                                        ),
                                        NeuCard(
                                          curveType: CurveType.flat,
                                          bevel: 10,
                                          decoration: NeumorphicDecoration(
                                            color: Theme.of(context).scaffoldBackgroundColor,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: FAProgressBar(
                                            backgroundColor: Colors.transparent,
                                            changeColorValue: 90,
                                            changeProgressColor: Colors.red,
                                            progressColor: Colors.blue,
                                            currentValue: utilization['cpu']['user_load'] + utilization['cpu']['system_load'],
                                            displayText: '%',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 20,
                              ),
                              Expanded(
                                child: NeuCard(
                                  curveType: CurveType.flat,
                                  decoration: NeumorphicDecoration(
                                    color: Theme.of(context).scaffoldBackgroundColor,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  bevel: 20,
                                  child: Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Image.asset(
                                              "assets/icons/ram.png",
                                              width: 50,
                                            ),
                                            SizedBox(
                                              width: 10,
                                            ),
                                            Text(
                                              "内存",
                                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                        SizedBox(
                                          height: 10,
                                        ),
                                        NeuCard(
                                          curveType: CurveType.flat,
                                          bevel: 10,
                                          decoration: NeumorphicDecoration(
                                            color: Theme.of(context).scaffoldBackgroundColor,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: FAProgressBar(
                                            backgroundColor: Colors.transparent,
                                            changeColorValue: 90,
                                            changeProgressColor: Colors.red,
                                            progressColor: Colors.blue,
                                            currentValue: utilization['memory']['real_usage'],
                                            displayText: '%',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(
                            height: 20,
                          ),
                          ...containers.map(_buildContainerItem).toList(),
                        ],
                      ),
                imageLoading
                    ? Center(
                        child: NeuCard(
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
                    : ListView.separated(
                        padding: EdgeInsets.all(20),
                        itemBuilder: (context, i) {
                          return _buildImageItem(images[i]);
                        },
                        separatorBuilder: (context, i) {
                          return SizedBox(
                            height: 20,
                          );
                        },
                        itemCount: images.length),
                registryLoading
                    ? Center(child: CupertinoActivityIndicator())
                    : ListView(
                        padding: EdgeInsets.all(20),
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text("注册表", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                              ),
                              NeuButton(
                                onPressed: _showAddRegistry,
                                decoration: NeumorphicDecoration(
                                  color: Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                bevel: 5,
                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Text("添加"),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          if (registries.isEmpty)
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text("暂无注册表", style: TextStyle(color: Colors.grey)),
                              ),
                            )
                          else
                            ...registries.map(_buildRegistryItem).toList(),
                        ],
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
