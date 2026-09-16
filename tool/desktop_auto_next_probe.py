"""Generate the auto-next source-method regression fixture.

Usage: python tool/desktop_auto_next_probe.py REPO_ROOT OUTPUT_TEST.dart
Run the generated Dart file with flutter test from a configured checkout.
The UI/backend dependencies are inert stubs; this is not a decoder test.
Each extraction emits a .binding.json with source and method SHA256 hashes.
"""
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]); out=pathlib.Path(sys.argv[2])
source=(root/'lib/desktop/playback/desktop_playback_screen.dart').read_text(encoding='utf-8')
names=['_onPositionChanged','_onPlayingChanged','_onBufferingChanged','_onCompletedChanged','_startAutoNextCountdown','_cancelAutoNext','_seekTo']
methods=[]
for name in names:
    start=source.index(('  Future<void> ' if name=='_seekTo' else '  void ')+name+'(')
    # Method bodies follow the parameter list, which may contain named parameters.
    body=source.index(') {',start)+2
    depth=0
    for end in range(body,len(source)):
        depth += (source[end]=='{')-(source[end]=='}')
        if depth==0: break
    methods.append(source[start:end+1])
prefix='''// Generated from production methods; inert UI/backend stubs, no mpv decoding.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
class _PlayerState {Duration duration=const Duration(seconds:100), position=Duration.zero; bool completed=false; double rate=1;}
class _Player { final state=_PlayerState(); Future<void> seek(Duration position) async {state.position=position; state.completed=false;} }
class _Weak {void onPosition(Duration d) {} void markSeek() {}}
class _Widget {Object? resolveEpisode=Object();}
class _Harness {
 bool mounted=true, _isLoading=false, _isPlaying=true, _pausedByUser=false, _isBuffering=false, _playbackCompleted=false, _controlsVisible=false, _autoNextSuppressed=false, _autoPlayEnabled=true, _showResumePrompt=false;
 int _autoNextSeconds=0, opened=0, _sourceChangeGeneration=0, _danmakuSeekRevision=0;
 double _playbackRate=1;
 Object? _errorMessage, _abLoopStart;
 Object? _nextEpisode=Object();
 final widget=_Widget(); final _player=_Player(); final _weakNetwork=_Weak();
 final _skipPromptKindNotifier=ValueNotifier<Object?>(null);
 final _viewRevision=ValueNotifier<int>(0);
 Timer? _autoNextTimer, _progressTimer, _directLinkTimer, _controlsHideTimer, _resumePromptTimer;
 void _updateView(VoidCallback update)=>update();
 void _syncSystemMediaControls() {} Future<void> _refreshSegmentedSubtitle(Duration d) async {}
 Object? _computeSkipPromptKind(Duration d)=>null;
 void _reportProgress() {} void _scheduleControlsHide() {} void _scheduleProgressReport() {}
 Future<void> _showNextEpisode() async {opened++;}
 double _validPlaybackRate(double value)=>value.isFinite && value>0 ? value : 1;
 void position(int ms){_player.state.position=Duration(milliseconds:ms);_onPositionChanged(_player.state.position);}
 void eof(){_player.state.completed=true;_onCompletedChanged(true);}
 void close(){mounted=false;_autoNextTimer?.cancel();_skipPromptKindNotifier.dispose();_viewRevision.dispose();}
'''
tests='''
}
void main(){
 for(final mode in ['pause','buffer','normal']) {
 testWidgets('pre-EOF $mode never advances on wall clock',(tester) async {
  final h=_Harness();addTearDown(h.close);h.position(95000);
  if(mode=='pause'){h._pausedByUser=true;h._onPlayingChanged(false);}
  if(mode=='buffer') h._onBufferingChanged(true);
  await tester.pump(const Duration(seconds:10));expect(h.opened,0);
 });}
 for(final rate in [0.5,1.0,2.0]) {
 testWidgets('rate $rate waits for EOF and then advances once',(tester) async {
  final h=_Harness();addTearDown(h.close);h._playbackRate=rate;h._player.state.rate=rate;
  h.position(95000);await tester.pump(const Duration(seconds:10));expect(h.opened,0);
  h.position(99000);h.eof();await tester.pump(const Duration(seconds:5));expect(h.opened,1);
  await tester.pump(const Duration(seconds:10));expect(h.opened,1);
 });}
 testWidgets('seek away cancels preview; seek back can preview again',(tester) async {
  final h=_Harness();addTearDown(h.close);h.position(95000);h.position(20000);
  expect(h._autoNextSeconds,0);await tester.pump(const Duration(seconds:10));expect(h.opened,0);
  h.position(99000);h.eof();await tester.pump(const Duration(seconds:5));expect(h.opened,1);
 });
 testWidgets('user cancellation lasts for this episode including seek and EOF',(tester) async {
  final h=_Harness();addTearDown(h.close);h.position(95000);h._cancelAutoNext();
  h.position(20000);h.position(99000);h.eof();await tester.pump(const Duration(seconds:10));expect(h.opened,0);
 });
 for(final mode in ['pause','buffer','error','loading','disabled','ab','unmounted','generation']) {
 testWidgets('EOF pending $mode cannot advance',(tester) async {
  final h=_Harness();addTearDown(h.close);h.eof();
  switch(mode){case 'pause':h._pausedByUser=true;h._onPlayingChanged(false);case 'buffer':h._onBufferingChanged(true);case 'error':h._errorMessage='error';case 'loading':h._isLoading=true;case 'disabled':h._autoPlayEnabled=false;case 'ab':h._abLoopStart=Object();case 'unmounted':h.mounted=false;case 'generation':h._sourceChangeGeneration++;}
  await tester.pump(const Duration(seconds:10));expect(h.opened,0);
  if(mode=='pause'||mode=='buffer'){
    h._onPlayingChanged(true);h._onBufferingChanged(false);
    await tester.pump(const Duration(seconds:5));expect(h.opened,1);
  }
 });}
 for (final cancelled in [false, true]) {
 testWidgets('EOF seek back inside final five seconds preserves cancellation=$cancelled',(tester) async {
  final h=_Harness();addTearDown(h.close);h.position(99000);h.eof();
  if(cancelled) h._cancelAutoNext();
  await h._seekTo(const Duration(seconds:98));h.position(98000);
  expect(h._playbackCompleted,false);
  h.eof();await tester.pump(const Duration(seconds:5));expect(h.opened,cancelled ? 0 : 1);
 });}
 testWidgets('EOF without preview keeps normal five second cancellation window',(tester) async {
  final h=_Harness();addTearDown(h.close);h.eof();
  await tester.pump(const Duration(seconds:4));expect(h.opened,0);
  await tester.pump(const Duration(seconds:1));expect(h.opened,1);
 });
}
'''
out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(prefix+'\n\n'.join(methods)+tests,encoding='utf-8')
out.with_suffix('.binding.json').write_text(json.dumps({'source':str(root),'source_sha256':hashlib.sha256(source.encode()).hexdigest(),'methods':dict(zip(names,[hashlib.sha256(m.encode()).hexdigest() for m in methods]))},indent=2),encoding='utf-8')
