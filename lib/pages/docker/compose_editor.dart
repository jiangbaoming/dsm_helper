import 'package:dsm_helper/widgets/neu_back_button.dart';
import 'package:flutter/material.dart';

/// compose YAML 编辑器（保存后通过 Navigator.pop 返回新内容）
class ComposeEditor extends StatefulWidget {
  final String title;
  final String content;
  ComposeEditor({this.title, this.content});
  @override
  _ComposeEditorState createState() => _ComposeEditorState();
}

class _ComposeEditorState extends State<ComposeEditor> {
  TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    _controller.text = widget.content ?? "";
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(context),
        title: Text(widget.title ?? "编辑 compose"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: Text("保存"),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: TextField(
            controller: _controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            style: TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(border: InputBorder.none, hintText: "在此编辑 compose YAML..."),
          ),
        ),
      ),
    );
  }
}
