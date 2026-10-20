# package:jni looks up these Kotlin coroutine types and members by name from
# Dart/native code. Keep their JVM names and signatures for Pigeon JNI calls
# used by shared_preferences_android. Flutter adds this file to release R8 rules.
-keep interface kotlin.coroutines.Continuation {
    public void resumeWith(java.lang.Object);
}

-keep class kotlin.Result {
    java.lang.Object value;
}

-keep class kotlin.Result$Failure {
    public <init>(java.lang.Throwable);
    java.lang.Throwable exception;
}

-keep class kotlin.Unit {
    public static kotlin.Unit INSTANCE;
}

-keep class kotlin.coroutines.intrinsics.CoroutineSingletons

# JNI looks up the method on IntrinsicsKt, but Kotlin declares it on the parent.
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt__IntrinsicsKt {
    public static java.lang.Object getCOROUTINE_SUSPENDED();
}
