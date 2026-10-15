import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_interactions.dart';
import 'app_ui.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'novel_feed_controller.dart';
import 'pages.dart' show DiscoverPage, openDetail;
import 'publication_catalog.dart';
import 'wenku_account.dart';

Future<bool> confirmNovelAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool reduceMotion = false,
}) async =>
    await showJellySheet<bool>(
      context: context,
      reduceMotion: reduceMotion,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Text(message),
            const SizedBox(height: 24),
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, true),
              child: Text(confirmLabel),
            ),
            const SizedBox(height: 8),
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, false),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    ) ==
    true;

class ArchiveFeaturePage extends StatelessWidget {
  const ArchiveFeaturePage({
    super.key,
    required this.title,
    required this.code,
    required this.child,
    this.actions = const [],
    this.canPop = true,
  });
  final String title, code;
  final Widget child;
  final List<Widget> actions;
  final bool canPop;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Atmosphere(
      child: GlassHeaderLayout(
        header: Row(
          children: [
            GlassIconButton(
              icon: CupertinoIcons.back,
              label: '返回',
              onPressed: canPop ? () => Navigator.pop(context) : null,
            ),
            Expanded(
              child: ArchiveRouteTitle(title: title, code: code),
            ),
            ...actions,
          ],
        ),
        body: child,
      ),
    ),
  );
}

EdgeInsets featurePadding(BuildContext context) => EdgeInsets.fromLTRB(
  24,
  MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight + 20,
  24,
  MediaQuery.paddingOf(context).bottom + 32,
);

class FeatureEntry extends StatelessWidget {
  const FeatureEntry({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ContentPanel(
    onTap: onTap,
    child: Row(
      children: [
        Icon(icon, size: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Icon(CupertinoIcons.chevron_right, size: 14),
      ],
    ),
  );
}

class FeatureError extends StatelessWidget {
  const FeatureError(this.text, {super.key});
  final String? text;
  @override
  Widget build(BuildContext context) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Semantics(
            liveRegion: true,
            child: Text(
              text!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        );
}

class WenkuAccountPage extends StatefulWidget {
  const WenkuAccountPage({
    super.key,
    required this.account,
    required this.state,
    required this.repository,
  });
  final WenkuAccount account;
  final LibraryState state;
  final NovelRepository repository;
  @override
  State<WenkuAccountPage> createState() => _WenkuAccountPageState();
}

class _WenkuAccountPageState extends State<WenkuAccountPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.account.initialize());
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work, String success) async {
    if (widget.account.busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await work();
      if (mounted) showNovelFeedback(context, success);
    } catch (_) {
      /* The account's live region displays the concrete failure. */
    }
  }

  Future<void> _login() async {
    if (widget.account.busy) return;
    final password = _password.text;
    _password.clear();
    TextInput.finishAutofillContext(shouldSave: false);
    await _run(() => widget.account.login(_username.text, password), '登录成功');
  }

  Future<void> _logout() async {
    final confirmed = await confirmNovelAction(
      context,
      title: '退出账号？',
      message: '仅退出云端账号，本机书架、阅读进度、书签与离线章节均保留。',
      confirmLabel: '退出账号',
      reduceMotion: widget.state.reduceMotion,
    );
    if (confirmed) await _run(widget.account.logout, '已退出账号');
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.account,
    builder: (context, _) {
      final account = widget.account;
      final profile = account.profile;
      return ArchiveFeaturePage(
        title: '文库账号',
        code: 'ACCOUNT / PERSONAL ARCHIVE',
        child: LoadedContentSequence(
          generation: (account.authenticated, profile?.id),
          child: ListView(
            key: ValueKey(account.authenticated),
            padding: featurePadding(context),
            children: [
              LoadedContentItem(
                index: 0,
                child: Text(
                  account.authenticated
                      ? profile?.displayName ?? '已登录'
                      : '连接你的文库',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                account.authenticated
                    ? '云书架与本机书架独立保存，合并时保留本机阅读进度。'
                    : '使用原版文库账号。未登录时仍可搜索、收藏到本机和离线阅读。',
              ),
              const SizedBox(height: 24),
              if (!account.authenticated)
                ContentPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('account-username'),
                        controller: _username,
                        enabled: !account.busy,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        maxLength: 254,
                        decoration: const InputDecoration(
                          labelText: '用户名 / 邮箱',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('account-password'),
                        controller: _password,
                        enabled: !account.busy,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        maxLength: 30,
                        onSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                          labelText: '密码',
                          counterText: '',
                          suffixIcon: IconButton(
                            tooltip: _obscure ? '显示密码' : '隐藏密码',
                            icon: Icon(
                              _obscure
                                  ? CupertinoIcons.eye
                                  : CupertinoIcons.eye_slash,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      GlassTextButton(
                        key: const ValueKey('account-login'),
                        onPressed: account.busy ? null : _login,
                        child: const Text('登录'),
                      ),
                    ],
                  ),
                )
              else ...[
                LoadedContentItem(
                  index: 1,
                  child: ContentPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (profile == null && account.busy)
                          const SizedBox(
                            height: 72,
                            child: LoadingSkeleton(
                              layout: SkeletonLayout.actions,
                            ),
                          )
                        else ...[
                          ArchiveCode(
                            profile == null
                                ? 'SESSION / READY'
                                : 'UID / ${profile.id}',
                          ),
                          const SizedBox(height: 12),
                          if (profile != null) ...[
                            Text(profile.username),
                            const SizedBox(height: 8),
                            Text(
                              '${profile.rank}  ·  ${profile.score} 积分  ·  ${profile.experience} 经验',
                            ),
                          ],
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          children: [
                            GlassTextButton(
                              key: const ValueKey('account-sign'),
                              onPressed: account.busy || account.signedToday
                                  ? null
                                  : () => _run(account.signIn, '今日签到已完成'),
                              child: Text(
                                account.signedToday ? '今日已签到' : '每日签到',
                              ),
                            ),
                            GlassTextButton(
                              onPressed: account.busy
                                  ? null
                                  : () => _run(account.refreshProfile, '账号已更新'),
                              child: const Text('刷新资料'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                LoadedContentItem(
                  index: 2,
                  child: FeatureEntry(
                    key: const ValueKey('account-cloud'),
                    title: '云书架',
                    subtitle: '查看、合并收藏；不覆盖阅读记录',
                    icon: CupertinoIcons.cloud,
                    onTap: account.busy
                        ? null
                        : () => pushNovelPage<void>(
                            context,
                            CloudBookshelfPage(
                              account: account,
                              state: widget.state,
                              repository: widget.repository,
                            ),
                            reduceMotion: widget.state.reduceMotion,
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                GlassTextButton(
                  key: const ValueKey('account-logout'),
                  onPressed: account.busy ? null : _logout,
                  child: const Text('退出账号'),
                ),
              ],
              if (account.busy) ...[
                const SizedBox(height: 20),
                const InlineSkeleton(label: '正在处理账号操作'),
                const SizedBox(height: 10),
                Text(account.operation ?? ''),
              ],
              FeatureError(account.error),
            ],
          ),
        ),
      );
    },
  );
}

class CloudBookshelfPage extends StatefulWidget {
  const CloudBookshelfPage({
    super.key,
    required this.account,
    required this.state,
    required this.repository,
  });
  final WenkuAccount account;
  final LibraryState state;
  final NovelRepository repository;
  @override
  State<CloudBookshelfPage> createState() => _CloudBookshelfPageState();
}

class _CloudBookshelfPageState extends State<CloudBookshelfPage> {
  String? _localError;
  bool _merging = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (widget.account.busy) return;
    try {
      await widget.account.refreshCloud();
    } catch (_) {}
  }

  Future<void> _merge() async {
    if (_merging || widget.account.busy) return;
    final confirmed = await confirmNovelAction(
      context,
      title: '合并云书架到本机？',
      message: '添加云端收藏。本机已有书籍、进度、书签和缓存保持不变。',
      confirmLabel: '合并收藏',
      reduceMotion: widget.state.reduceMotion,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _merging = true;
      _localError = null;
    });
    try {
      final count = await widget.account.mergeCloudToLocal(widget.state);
      if (mounted) showNovelFeedback(context, '已添加 $count 本云端收藏到本机');
    } catch (error) {
      if (mounted) {
        setState(() => _localError = WenkuAccount.describeError(error));
      }
    } finally {
      if (mounted) setState(() => _merging = false);
    }
  }

  Future<void> _upload() async {
    if (_merging || widget.account.busy) return;
    final confirmed = await confirmNovelAction(
      context,
      title: '合并本机收藏到云端？',
      message: '仅上传云端没有的本机收藏。不会删除云端书籍，也不上传正文或阅读记录。',
      confirmLabel: '合并到云端',
      reduceMotion: widget.state.reduceMotion,
    );
    if (!confirmed || !mounted) return;
    try {
      final result = await widget.account.uploadMissing(widget.state.shelf);
      if (mounted) {
        showNovelFeedback(
          context,
          result.remaining.isEmpty
              ? '云书架已合并 · 新增 ${result.uploaded.length} 本'
              : '已完成 ${result.uploaded.length} 本，剩余 ${result.remaining.length} 本可重试',
        );
      }
    } catch (_) {}
  }

  Future<void> _remove(CloudBook book) async {
    if (widget.account.busy || _merging) return;
    final confirmed = await confirmNovelAction(
      context,
      title: '移出云书架？',
      message:
          '「${book.title.isEmpty ? '书籍 ${book.id}' : book.title}」的本机收藏、进度及缓存仍保留。',
      confirmLabel: '移出云书架',
      reduceMotion: widget.state.reduceMotion,
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.account.removeCloud(book.id);
    } catch (_) {}
  }

  Future<void> _open(CloudBook book) async {
    final novel =
        widget.state.cachedNovel(book.id) ??
        Novel(
          id: book.id,
          title: book.title.isEmpty ? '书籍 ${book.id}' : book.title,
          author: '',
          genre: '轻小说',
          summary: '',
          colors: const [Color(0xFF202020), Color(0xFF333333)],
          lastUpdate: book.updated,
          coverUrl:
              'https://img.wenku8.com/image/${book.id ~/ 1000}/${book.id}/${book.id}s.jpg',
        );
    openDetail(context, novel, widget.state, widget.repository);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.account, widget.state]),
    builder: (context, _) {
      final account = widget.account;
      final books = account.cloudBooks;
      final busy = account.busy || _merging;
      return ArchiveFeaturePage(
        title: '云书架',
        code: 'CLOUD / COLLECTION',
        actions: [
          GlassIconButton(
            icon: CupertinoIcons.refresh,
            label: '刷新云书架',
            onPressed: busy ? null : _refresh,
          ),
        ],
        child: LoadedContentSequence(
          generation: books,
          child: ListView.builder(
            padding: featurePadding(context),
            itemCount: 1 + (books?.length ?? 0),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sectionHeader(
                      context,
                      '云端收藏',
                      books == null ? '' : '${books.length} 本',
                    ),
                    const SizedBox(height: 12),
                    const Text('两端只合并收藏。移出云端不会删除本机数据；退出账号也不影响本机阅读。'),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        GlassTextButton(
                          key: const ValueKey('cloud-download'),
                          onPressed: busy || books == null ? null : _merge,
                          child: const Text('合并到本机'),
                        ),
                        GlassTextButton(
                          key: const ValueKey('cloud-upload'),
                          onPressed: busy || books == null ? null : _upload,
                          child: const Text('合并到云端'),
                        ),
                      ],
                    ),
                    FeatureError(_localError ?? account.error),
                    if (busy)
                      const SizedBox(
                        height: 72,
                        child: LoadingSkeleton(layout: SkeletonLayout.actions),
                      ),
                    if (books?.isEmpty == true)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(child: Text('云书架还没有收藏')),
                      ),
                    const SizedBox(height: 20),
                  ],
                );
              }
              final book = books![index - 1];
              return LoadedContentItem(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ContentPanel(
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _open(book),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  book.title.isEmpty
                                      ? '书籍 ${book.id}'
                                      : book.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (book.latestChapter.isNotEmpty) ...[
                                  const SizedBox(height: 7),
                                  Text(
                                    book.latestChapter,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                ArchiveCode(
                                  '${book.updated}  /  ${widget.state.contains(book.id) ? 'LOCAL + CLOUD' : 'CLOUD'}',
                                ),
                              ],
                            ),
                          ),
                        ),
                        GlassIconButton(
                          icon: CupertinoIcons.minus_circle,
                          label: '移出云书架 ${book.id}',
                          onPressed: busy ? null : () => _remove(book),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

class PublicationLibraryPage extends StatefulWidget {
  const PublicationLibraryPage({
    super.key,
    required this.catalog,
    required this.repository,
    required this.state,
    this.account,
  });
  final PublicationCatalog catalog;
  final NovelRepository repository;
  final LibraryState state;
  final WenkuAccount? account;
  @override
  State<PublicationLibraryPage> createState() => _PublicationLibraryPageState();
}

class _PublicationLibraryPageState extends State<PublicationLibraryPage> {
  List<PublicationLibrary> _libraries = const [];
  PublicationLibrary? _selected;
  NovelFeedController? _feed;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final libraries = await widget.catalog.publicationLibraries(
        refresh: true,
      );
      if (mounted) {
        _libraries = libraries;
        _select(libraries.first);
      }
    } catch (error) {
      if (mounted) setState(() => _error = WenkuAccount.describeError(error));
    }
  }

  void _select(PublicationLibrary library) {
    if (_selected?.id == library.id) return;
    _feed?.dispose();
    setState(() {
      _selected = library;
      _feed = NovelFeedController(
        PublicationNovelRepository(widget.repository, widget.catalog, library),
        initialItems: 60,
      );
    });
    _feed!.loadInitial();
  }

  Future<void> _choose(BuildContext anchor) async {
    final selected = await showGlassMenu<PublicationLibrary>(
      context: anchor,
      reduceMotion: widget.state.reduceMotion,
      builder: (menuContext) => SizedBox(
        width: 260,
        height: MediaQuery.sizeOf(menuContext).height * .6,
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: _libraries.length,
          itemBuilder: (context, index) => GlassTextButton(
            onPressed: () => Navigator.pop(menuContext, _libraries[index]),
            child: Row(
              children: [
                Expanded(child: Text(_libraries[index].name)),
                if (_selected?.id == _libraries[index].id)
                  const Icon(CupertinoIcons.checkmark, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted && selected != null) _select(selected);
  }

  Future<void> _loginForLibrary() async {
    final account = widget.account;
    if (account == null) return;
    await pushNovelPage<void>(
      context,
      WenkuAccountPage(
        account: account,
        state: widget.state,
        repository: widget.repository,
      ),
      reduceMotion: widget.state.reduceMotion,
    );
    if (mounted && account.authenticated) await _feed?.refresh();
  }

  Widget _catalogBody(BuildContext context) {
    final failure = _feed?.error;
    if (failure is WenkuApiError &&
        failure.code == 4 &&
        widget.account != null) {
      return ContentNotice(
        icon: CupertinoIcons.person_crop_circle,
        title: '此分类需要文库账号',
        message: '文库服务要求登录后读取出版分类。最近更新、排行榜和搜索仍可直接使用。',
        actionLabel: '登录账号',
        onRetry: _loginForLibrary,
      );
    }
    return DiscoverPage(
      key: ValueKey(_selected!.id),
      books: const [],
      state: widget.state,
      repository: widget.repository,
      onSearch: () {},
      showHeader: false,
      feed: _feed,
      categoryTitle: _selected!.name,
      onChooseCategory: _choose,
    );
  }

  @override
  void dispose() {
    _feed?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '出版文库',
    code: 'CATALOG / PUBLICATION',
    child: _selected == null
        ? (_error != null
              ? ContentNotice(
                  icon: CupertinoIcons.wifi_exclamationmark,
                  title: '文库分类加载失败',
                  message: _error!,
                  onRetry: _load,
                )
              : const LibrarySkeleton())
        : AnimatedBuilder(
            animation: _feed!,
            builder: (context, _) => _catalogBody(context),
          ),
  );
}
