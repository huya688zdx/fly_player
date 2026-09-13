#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Control.h>
#include <iostream>
#include <string>

std::string json(const winrt::hstring& value) {
  auto raw=winrt::to_string(value); std::string out="\"";
  for(char c:raw) { if(c=='"'||c=='\\') out+='\\'; if(c=='\n') out+="\\n"; else if(c=='\r') out+="\\r"; else out+=c; }
  return out+'"';
}
// Uses the player's existing Windows media session. This does not open, decode,
// proxy or identify any file. SMTC position is rounded to seconds by the player;
// accepted commands are not reported as settled OPED actions.
int wmain(int argc, wchar_t** argv) {
  try {
    winrt::init_apartment();
    auto manager=winrt::Windows::Media::Control::GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
    if (argc > 1) {
      if (argc != 4 || std::wstring(argv[1]) != L"--seek-ms") return 2;
      auto target=std::stoll(argv[2]);
      auto sessions=manager.GetSessions();
      // The observed B run owns the sole active Fly session. Never select an
      // arbitrary current session when another program is also playing.
      if (sessions.Size()!=1) { std::cerr<<"Expected exactly one media session\n"; return 3; }
      auto session=sessions.GetAt(0);
      auto media=session.TryGetMediaPropertiesAsync().get();
      if (session.SourceAppUserModelId()!=L"fly_player.exe" || media.Subtitle()!=argv[3]) { std::cerr<<"Media session identity changed\n"; return 4; }
      if (target<0 || target>=session.GetTimelineProperties().EndTime().count()/10000) return 5;
      if (!session.TryPauseAsync().get()) return 6;
      bool accepted=session.TryChangePlaybackPositionAsync(target*10000).get();
      std::cout<<"{\"seek_requested_ms\":"<<target<<",\"command_accepted\":"<<(accepted?"true":"false")<<",\"settled_observation\":false}\n";
      if (!accepted) return 7;
      Sleep(700);
    }
    for(auto session:manager.GetSessions()) {
      auto timeline=session.GetTimelineProperties(); auto media=session.TryGetMediaPropertiesAsync().get();
      std::cout << "{\"app\":" << json(session.SourceAppUserModelId()) << ",\"title\":" << json(media.Title())
        << ",\"subtitle\":" << json(media.Subtitle()) << ",\"position_ms\":" << timeline.Position().count()/10000
        << ",\"duration_ms\":" << timeline.EndTime().count()/10000 << ",\"position_precision_ms\":1000,\"status\":" << (int)session.GetPlaybackInfo().PlaybackStatus() << "}\n";
    }
  } catch (const winrt::hresult_error& e) { std::cerr<<"SMTC read failed: "<<std::hex<<(unsigned)e.code()<<"\n"; return 1; }
}
