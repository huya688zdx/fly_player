-keep class is.xyz.mpv.MPVLib {
    public static void event(int);
    public static void logMessage(java.lang.String, int, java.lang.String);
    public static void eventProperty(java.lang.String);
    public static void eventProperty(java.lang.String, long);
    public static void eventProperty(java.lang.String, boolean);
    public static void eventProperty(java.lang.String, java.lang.String);
    public static void eventProperty(java.lang.String, double);
    public int onFileLoaded();
    public int onEndFile();
    public int propertyEvent();
}

-keep class is.xyz.mpv.MPVLib$EventObserver { *; }
-keep class is.xyz.mpv.MPVLib$LogObserver { *; }

-keep class com.baidu.paddle.fastdeploy.** { *; }
-keepclassmembers class com.baidu.paddle.fastdeploy.** { *; }
