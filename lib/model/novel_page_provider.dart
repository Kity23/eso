import 'dart:io';
import 'dart:ui' as ui;

import 'package:eso/api/api.dart';
import 'package:eso/api/api_manager.dart';
import 'package:eso/database/history_item_manager.dart';
import 'package:eso/database/search_item_manager.dart';
import 'package:eso/global.dart';
import 'package:eso/utils.dart';
import 'package:eso/utils/cache_util.dart';
import 'package:flutter_share/flutter_share.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:screen/screen.dart';
import 'package:windows_speak/windows_speak.dart';
import '../database/search_item.dart';
import 'package:flutter/material.dart';

import '../profile.dart';
import 'package:text_composition/text_composition.dart';

class NovelPageProvider with ChangeNotifier {
  final SearchItem searchItem;
  int _progress;
  int get progress => _progress;
  List<String> _paragraphs;
  List<String> get paragraphs => _paragraphs;
  PageController _controller;
  PageController get controller => _controller;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _showMenu;
  bool get showMenu => _showMenu;

  set showMenu(bool value) {
    if (_showMenu != value) {
      _showMenu = value;
      if (value == false) _showChapter = false;
      notifyListeners();
    }
  }

  bool _showSetting;
  bool get showSetting => _showSetting;
  set showSetting(bool value) {
    if (_showSetting != value) {
      _showSetting = value;
      notifyListeners();
    }
  }

  bool _showChapter;
  bool get showChapter => _showChapter;
  set showChapter(bool value) {
    if (_showChapter != value) {
      _showChapter = value;
      notifyListeners();
    }
  }

  bool _useSelectableText;
  bool get useSelectableText => _useSelectableText;
  set useSelectableText(bool value) {
    if (value != _useSelectableText) {
      _useSelectableText = value;
      notifyListeners();
    }
  }

  double _brightness;
  double get brightness => _brightness;
  set brightness(double value) {
    if ((value - _brightness).abs() > 0.005) {
      _brightness = value;
      Screen.setBrightness(brightness);
    }
  }

  bool keepOn;
  void setKeepOn(bool value) {
    if (value != keepOn) {
      keepOn = value;
      Screen.keepOn(keepOn);
    }
  }

  final double height;

  NovelPageProvider({this.searchItem, this.keepOn, this.height, Profile profile}) {
    _tts.setCompletionHandler(nextPara);
    WindowsSpeak.handleComplete = nextPara;
    _brightness = 0.5;
    _isLoading = false;
    _showChapter = false;
    _showMenu = false;
    _showSetting = false;
    _useSelectableText = false;
    _controller = PageController();
    _progress = 0;
    if (searchItem.chapters?.length == 0 &&
        SearchItemManager.isFavorite(searchItem.originTag, searchItem.url)) {
      searchItem.chapters = SearchItemManager.getChapter(searchItem.id);
    }
    _initContent(profile);
  }

  void _initContent(Profile profile) async {
    if (Platform.isAndroid || Platform.isIOS) {
      _brightness = await Screen.brightness;
      if (_brightness > 1) {
        _brightness = 0.5;
      }
      if (keepOn) {
        Screen.keepOn(keepOn);
      }
    }
    _paragraphs = await loadContent(searchItem.durChapterIndex);
    if (this.mounted) notifyListeners();
  }

  Map<int, List<String>> _cache;
  CacheUtil _fileCache;
  static bool _requestPermission = false;

  void clearCurrent() async {
    _cache.clear();
    await _fileCache.putData("list.json", <int>[], hashCodeKey: false);
  }

  /// 刷新当前章节
  void refreshCurrent() async {
    if (isLoading) return;
    _isLoading = true;
    _showChapter = false;
    notifyListeners();
    final chapter = searchItem.chapters[searchItem.durChapterIndex];
    final content = await APIManager.getContent(searchItem.originTag, chapter.url);
    chapter.contentUrl = API.contentUrl;
    _paragraphs = content.join("\n").split(RegExp(r"\n\s*|\s{2,}"));
    _cache[searchItem.durChapterIndex] = _paragraphs;
    await _fileCache.putData('${searchItem.durChapterIndex}.txt', _paragraphs.join("\n"),
        hashCodeKey: false, shouldEncode: false);

    // 强制刷新界面
    buildTextComposition(Profile());
    // 强制刷新界面

    searchItem.lastReadTime = DateTime.now().microsecondsSinceEpoch;
    _isLoading = false;
    notifyListeners();
  }

  // 清理内存缓存
  _clearMemCache(int index) {
    if (_cache == null) return;
    int minIndex = index - 2;
    int maxIndex = index + 2;
    _cache.forEach((key, value) {
      if ((key <= minIndex || key >= maxIndex) && (key != index)) _cache.remove(key);
    });
  }

  _updateCache(int index, List<String> content) async {
    final _content = content.join("\n").split(RegExp(r"\n\s*|\s{2,}"));
    _cache = {index: _content};
    final r = await _fileCache.putData('$index.txt', _content.join("\n"),
        hashCodeKey: false, shouldEncode: false);
    if (r && _content.join("").trim().isNotEmpty) {
      _cacheChapterIndex.add(index);
      await _fileCache.putData("list.json", _cacheChapterIndex, hashCodeKey: false);
    }
  }

  bool _exportLoading;
  bool get exportLoading => _exportLoading;

  TextEditingController exportChapterName = TextEditingController(text: "\$name");

  void exportCache({bool isShare = false, bool isSaveLocal = false}) async {
    if (_exportLoading == true) {
      Utils.toast("正在导出...");
      return;
    }
    _exportLoading = true;
    Utils.toast("开始导出已缓存章节");

    try {
      final chapters = searchItem.chapters;
      final export = <String>[
        "书名: ${searchItem.name}",
        "作者: ${searchItem.author}",
        "来源: ${searchItem.url}",
        // ...chapters.map((ch) => ch.name).toList(),
      ];
      for (final index in List.generate(chapters.length, (index) => index)) {
        String temp;
        if (cacheChapterIndex.contains(index)) {
          temp = await _fileCache.getData("$index.txt",
              shouldDecode: false, hashCodeKey: false);
        } else if (_cache != null && _cache[index] != null && _cache[index].isNotEmpty) {
          temp = _cache[index].join("\n");
        }
        export.add("");
        export.add(exportChapterName.text
            .replaceAll("\$index", (index + 1).toString())
            .replaceAll("\$name", chapters[index].name));
        export.add("");
        if (temp != null && temp.isNotEmpty) {
          export.add(temp);
        } else {
          export.add("未缓存或内容为空");
        }
      }
      final cache = CacheUtil(backup: true, basePath: "txt");
      final name = "${searchItem.name}_${searchItem.author}" +
          "searchItem${searchItem.id}".hashCode.toString() +
          ".txt";
      await cache.putData(name, export.join("\n"),
          hashCodeKey: false, shouldEncode: false);
      final filePath = await cache.cacheDir() + name;
      Utils.toast("成功导出到 $filePath");
      if (isShare == true) {
        await FlutterShare.shareFile(title: name, filePath: filePath);
      }
    } catch (e) {
      Utils.toast("失败 $e");
    }
    _exportLoading = false;
  }

  bool _autoCacheDoing;
  bool get autoCacheDoing => _autoCacheDoing == true;
  int _autoCacheToken;
  void _updateCacheToken() => _autoCacheToken = DateTime.now().millisecondsSinceEpoch;
  void toggleAutoCache() {
    if (_autoCacheDoing == null || _autoCacheDoing == false) {
      _autoCacheDoing = true;
      Utils.toast("开始自动缓存");
      notifyListeners();
      _updateCacheToken();
      _autoCacheTask(_autoCacheToken);
    } else {
      _updateCacheToken();
      _autoCacheDoing = false;
      Utils.toast("取消自动缓存");
      notifyListeners();
    }
  }

  _autoCacheTask(final int token) async {
    final chapters = searchItem.chapters;
    final id = searchItem.originTag;
    for (final index in List.generate(chapters.length, (index) => index)) {
      if (!autoCacheDoing || token != _autoCacheToken) break;
      if (cacheChapterIndex.contains(index)) continue;
      try {
        final chapter = chapters[index];
        final content = await APIManager.getContent(id, chapter.url);
        chapter.contentUrl = API.contentUrl;
        final c = content.join("\n").split(RegExp(r"\n\s*|\s{2,}")).join("\n");
        final r = await _fileCache.putData('$index.txt', c,
            hashCodeKey: false, shouldEncode: false);
        if (r && c.trim().isNotEmpty) {
          _cacheChapterIndex.add(index);
          await _fileCache.putData("list.json", _cacheChapterIndex, hashCodeKey: false);
        }
        notifyListeners();
      } catch (e) {}
    }
    _autoCacheDoing = false;
    notifyListeners();
    Utils.toast("自动缓存 已完成");
  }

  List<int> _cacheChapterIndex;
  List<int> get cacheChapterIndex => _cacheChapterIndex;

  String get cacheName => "searchItem${searchItem.id}";

  _initFileCache() async {
    if (_fileCache == null) {
      _fileCache = CacheUtil(cacheName: cacheName);
      if (!_requestPermission) {
        _requestPermission = true;
        await _fileCache.requestPermission();
      }
      final temp = await _fileCache.getData("list.json", hashCodeKey: false);
      if (temp != null && temp is List && temp.isNotEmpty) {
        _cacheChapterIndex = temp.map((e) => e as int).toList();
      } else {
        _cacheChapterIndex = <int>[];
        await _fileCache.putData("list.json", _cacheChapterIndex, hashCodeKey: false);
      }
    }
  }

  Future<List<String>> _realLoadContent(int index, [bool useCache = true]) async {
    if (useCache) {
      if (_fileCache == null) await _initFileCache();
      final resp =
          await _fileCache.getData('$index.txt', hashCodeKey: false, shouldDecode: false);
      if (resp != null && resp is String && resp.isNotEmpty) {
        final p = resp.split("\n");
        if (_cache == null) {
          _cache = {index: p};
        } else {
          _cache[index] = p;
        }
        return p;
      }
    }
    final chapter = searchItem.chapters[index];
    List<String> result = await APIManager.getContent(searchItem.originTag, chapter.url);
    chapter.contentUrl = API.contentUrl;
    _updateCache(index, result);
    return result;
  }

  _cacheNextChapter(int index) async {
    if (index < searchItem.chapters.length - 1 && _cache[index + 1] == null) {
      Future.delayed(Duration(milliseconds: 200), () async {
        if (_cache[index + 1] == null) {
          await _realLoadContent(index + 1, true);
          if (index < searchItem.durChapterIndex + 3) _cacheNextChapter(index + 1);
        }
      });
    }
  }

  /// 加载章节内容
  Future<List<String>> loadContent(int index,
      {bool useCache = true, VoidCallback onWait}) async {
    /// 检查当前章节
    if (_cache == null) {
      if (onWait != null) onWait();
      await _realLoadContent(index, useCache);
    } else if (_cache[index] == null) {
      if (onWait != null) onWait();
      await _realLoadContent(index, useCache);
    } else if (_cache.length > 16) {
      _clearMemCache(index);
    }

    /// 缓存下一个章节
    _cacheNextChapter(index);
    return _cache[index];
  }

  /// 加载指定章节
  Future<List<String>> loadChapter(int chapterIndex,
      {bool useCache = true,
      bool notify = true,
      bool changeCurChapter = true,
      bool lastPage}) async {
    _showChapter = false;
    if (isLoading || chapterIndex < 0 || chapterIndex >= searchItem.chapters.length)
      return null;
    if (notify) _isLoading = true;
    var _data;
    try {
      _data = await loadContent(chapterIndex, useCache: useCache, onWait: () {
        if (notify) notifyListeners();
      });
    } catch (e) {
      print("加载失败：$e");
    }
    if (_data == null) {
      if (this.mounted) {
        _isLoading = false;
        if (notify) notifyListeners();
      }
      throw Future.error('加载章节失败：$chapterIndex');
    }

    if (changeCurChapter) {
      _paragraphs = _data;
      await updateSearchItem(chapterIndex, lastPage);
    } else if (lastPage == true) {
      searchItem.durContentIndex = 0x7fffffff;
    }

    if (changeCurChapter) {
      // 滚动模式
      if (_readSetting?.pageSwitch != Profile.novelNone) {
        _readSetting.durChapterIndex = searchItem.durChapterIndex;
        buildTextComposition(Profile());
        // _controller = PageController(initialPage: currentPage);
        _controller.jumpToPage(_currentPage - 1);
      }
    }

    if (notify && this.mounted) {
      _isLoading = false;
      notifyListeners();
    }
    return _data;
  }

  /// 更新当前章节信息
  updateSearchItem(int chapterIndex, [bool lastPage]) async {
    searchItem.durChapter = searchItem.chapters[chapterIndex].name;
    searchItem.durContentIndex = lastPage == true ? 0x7fffffff : 1;
    searchItem.lastReadTime = DateTime.now().microsecondsSinceEpoch;
    searchItem.durChapterIndex = chapterIndex;
    await SearchItemManager.saveSearchItem();
    HistoryItemManager.insertOrUpdateHistoryItem(searchItem);
    await HistoryItemManager.saveHistoryItem();
  }

  int _currentPage;

  /// 当前页
  int get currentPage => _currentPage;
  set currentPage(int value) {
    if (value > 0 && value < textComposition.pageCount) {
      _currentPage = value + 1;
      searchItem.durContentIndex =
          (_currentPage * 10000 / textComposition.pageCount).floor();
    }
  }

  void tapNextPage() {
    if (_currentPage < textComposition.pageCount) {
      _currentPage++;
      searchItem.durContentIndex =
          (_currentPage * 10000 / textComposition.pageCount).floor();
      if (_readSetting.pageSwitch == Profile.novelNone) {
        notifyListeners();
      } else {
        _controller.jumpToPage(_currentPage - 1);
      }
    } else {
      loadChapter(searchItem.durChapterIndex + 1);
    }
  }

  void tapLastPage() {
    if (_currentPage > 1) {
      _currentPage--;
      searchItem.durContentIndex =
          (_currentPage * 10000 / textComposition.pageCount).floor();
      if (_readSetting.pageSwitch == Profile.novelNone) {
        notifyListeners();
      } else {
        _controller.jumpToPage(_currentPage - 1);
      }
    } else {
      loadChapter(searchItem.durChapterIndex - 1, lastPage: true);
    }
  }

  Future<bool> addToFavorite() async {
    if (SearchItemManager.isFavorite(searchItem.originTag, searchItem.url)) {
      return null;
    }
    return SearchItemManager.addSearchItem(searchItem);
  }

  @override
  void dispose() {
    if (Platform.isAndroid) {
      Screen.setBrightness(-1.0);
      Screen.keepOn(false);
    } else if (Platform.isIOS) {
      Screen.keepOn(false);
    }
    _updateCacheToken();
    _autoCacheDoing = false;
    _paragraphs?.clear();
    _controller?.dispose();
    () async {
      searchItem.lastReadTime = DateTime.now().microsecondsSinceEpoch;
      await SearchItemManager.saveSearchItem();
      HistoryItemManager.insertOrUpdateHistoryItem(searchItem);
      await HistoryItemManager.saveHistoryItem();
    }();
    _cache?.clear();
    _isLoading = null;
    exportChapterName.dispose();
    super.dispose();
  }

  bool get mounted => _isLoading != null;
  ReadSetting _readSetting;
  bool didUpdateReadSetting(Profile profile, Size size) {
    if (null == _readSetting ||
        null == textComposition ||
        _readSetting.didUpdate(profile, searchItem.durChapterIndex, size)) {
      _readSetting = ReadSetting.fromProfile(profile, searchItem.durChapterIndex, size);
      return true;
    }
    if (_readSetting.durChapterIndex != searchItem.durChapterIndex) {
      _readSetting.durChapterIndex = searchItem.durChapterIndex;
      return true;
    }
    if (_readSetting.pageSwitch != profile.novelPageSwitch) {
      _readSetting.pageSwitch = profile.novelPageSwitch;
      return true;
    }
    return false;
  }

  final _tts = FlutterTts();

  speakS(String s) {
    if (Global.isDesktop) {
      WindowsSpeak.speak(s);
    } else {
      _tts.speak(s);
    }
  }

  int _speakParaIndex = 0;

  stop() {
    if (Global.isDesktop) {
      WindowsSpeak.release();
    } else {
      _tts.stop();
    }
  }

  void speak() {
    if (_paragraphs.isEmpty) {
      Utils.toast("请等待解析结束");
      return;
    }
    if (_speakParaIndex < 0) {
      _speakParaIndex = -1;
      speakS('已经是本章开始');
      Utils.toast("已经是本章开始");
      return;
    }
    if (_speakParaIndex >= _paragraphs.length) {
      _speakParaIndex = _paragraphs.length;
      speakS('本章已经结束');
      Utils.toast("本章已经结束");
      return;
    }
    speakS(_paragraphs[_speakParaIndex]);
  }

  void nextPara() async {
    if (_speakParaIndex == _paragraphs.length) {
      Utils.toast("本章已经结束");
      stop();
      return;
    }
    _speakParaIndex++;
    speak();
  }

  void prevPara() async {
    _speakParaIndex--;
    speak();
  }

  TextComposition _textComposition;
  TextComposition get textComposition => _textComposition;
  Widget getTextCompositionPage([int page]) {
    return _textComposition.getPageWidget(pageIndex: page ?? (_currentPage - 1));
  }

  /// 文字排版部分
  void buildTextComposition(Profile profile) {
    print("** buildTextComposition start ${DateTime.now()}");
    if (paragraphs == null || paragraphs.isEmpty) return;

    MediaQueryData mediaQueryData = MediaQueryData.fromWindow(ui.window);
    final width = mediaQueryData.size.width - profile.novelLeftPadding * 2;
    final height = mediaQueryData.size.height -
        profile.novelTopPadding * 2 -
        (profile.showNovelInfo == true ? 32 : 0) -
        mediaQueryData.padding.top;

    _textComposition = TextComposition(
      boxSize: Size(width > 600 ? (width - 40) / 2 : width, height),
      columnCount: width > 600 ? 2 : 1,
      columnGap: 40,
      paragraph: profile.novelParagraphPadding,
      title: searchItem.durChapter,
      titleStyle: TextStyle(
        fontFamily: profile.novelFontFamily,
        fontSize: profile.novelFontSize + 2,
        height: profile.novelHeight,
        fontWeight: FontWeight.bold,
        color: Color(profile.novelFontColor),
      ),
      paragraphs: paragraphs,
      style: TextStyle(
        fontFamily: profile.novelFontFamily,
        fontSize: profile.novelFontSize,
        height: profile.novelHeight,
        color: Color(profile.novelFontColor),
      ),
      shouldJustifyHeight: true,
    );
    _currentPage =
        (searchItem.durContentIndex * _textComposition.pageCount / 10000).round();
    if (_currentPage < 1) {
      _currentPage = 1;
    } else if (_currentPage > _textComposition.pageCount) {
      _currentPage = _textComposition.pageCount;
    }
    print("** buildTextComposition end   ${DateTime.now()}");
  }

  void share() async {
    await FlutterShare.share(
      title: '亦搜 eso',
      text:
          '${searchItem.name.trim()}\n${searchItem.author.trim()}\n\n${searchItem.description.trim()}\n\n${searchItem.url}',
      //linkUrl: '${searchItem.url}',
      chooserTitle: '选择分享的应用',
    );
  }
}

class ReadSetting {
  double fontSize;
  double height;
  double topPadding;
  double leftPadding;
  double paragraphPadding;
  int pageSwitch;
  int indentation;
  int durChapterIndex;
  Size size;
  bool showInfo;

  ReadSetting.fromProfile(Profile profile, this.durChapterIndex, Size size) {
    fontSize = profile.novelFontSize;
    height = profile.novelHeight;
    leftPadding = profile.novelLeftPadding;
    topPadding = profile.novelTopPadding;
    paragraphPadding = profile.novelParagraphPadding;
    pageSwitch = profile.novelPageSwitch;
    indentation = profile.novelIndentation;
    this.size = size;
    showInfo = profile.showNovelInfo;
  }

  bool didUpdate(Profile profile, int durChapterIndex, Size size) {
    if ((fontSize - profile.novelFontSize).abs() < 0.1 &&
        (height - profile.novelHeight).abs() < 0.05 &&
        (leftPadding - profile.novelLeftPadding).abs() < 0.1 &&
        (topPadding - profile.novelTopPadding).abs() < 0.1 &&
        (paragraphPadding - profile.novelParagraphPadding).abs() < 0.1 &&
        pageSwitch == profile.novelPageSwitch &&
        indentation == profile.novelIndentation &&
        this.durChapterIndex == durChapterIndex &&
        showInfo == profile.showNovelInfo && 
        this.size == size) {
      return false;
    }
    return true;
  }
}
