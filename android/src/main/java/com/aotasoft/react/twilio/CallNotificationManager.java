package com.aotasoft.react.twilio;

import android.annotation.SuppressLint;
import android.app.ActivityManager;
import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Build;
import android.os.Bundle;
import android.service.notification.StatusBarNotification;
import android.support.v4.BuildConfig;
import android.support.v4.app.NotificationCompat;
import android.util.Log;
import android.view.WindowManager;

import com.evollu.react.fcm.R;
import com.facebook.react.bridge.ReactApplicationContext;
import com.twilio.voice.CallInvite;

import java.util.List;

import static android.content.Context.ACTIVITY_SERVICE;

//import android.app.NotificationChannel;


public class CallNotificationManager {

    private static final String VOICE_CHANNEL = "default";

    private NotificationCompat.InboxStyle inboxStyle = new NotificationCompat.InboxStyle();

    public CallNotificationManager() {
    }

    public int getApplicationImportance(ReactApplicationContext context) {
        ActivityManager activityManager = (ActivityManager) context.getSystemService(ACTIVITY_SERVICE);
        if (activityManager == null) {
            return 0;
        }
        List<ActivityManager.RunningAppProcessInfo> processInfos = activityManager.getRunningAppProcesses();
        if (processInfos == null) {
            return 0;
        }

        for (ActivityManager.RunningAppProcessInfo processInfo : processInfos) {
            if (processInfo.processName.equals(context.getApplicationInfo().packageName)) {
                return processInfo.importance;
            }
        }
        return 0;
    }

    public Class getMainActivityClass(ReactApplicationContext context) {
        String packageName = context.getPackageName();
        Intent launchIntent = context.getPackageManager().getLaunchIntentForPackage(packageName);
        String className = launchIntent.getComponent().getClassName();
        try {
            return Class.forName(className);
        } catch (ClassNotFoundException e) {
            e.printStackTrace();
            return null;
        }
    }

    @SuppressLint("WrongConstant")
    public Intent getLaunchIntent(ReactApplicationContext context,
                                  int notificationId,
                                  CallInvite callInvite,
                                  Boolean shouldStartNewTask,
                                  int appImportance
    ) {
        Intent launchIntent = new Intent(context, getMainActivityClass(context));

        int launchFlag = Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP;
        if (shouldStartNewTask || appImportance != ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) {
            launchFlag = Intent.FLAG_ACTIVITY_NEW_TASK;
        }

        launchIntent.setAction(TwilioVoiceModule.ACTION_INCOMING_CALL)
                .putExtra(TwilioVoiceModule.INCOMING_CALL_NOTIFICATION_ID, notificationId)
                .addFlags(
                        launchFlag +
                                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED +
                                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD +
                                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON +
                                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                );

        if (callInvite != null) {
            launchIntent.putExtra(TwilioVoiceModule.INCOMING_CALL_INVITE, callInvite);
        }
        return launchIntent;
    }

    @SuppressLint("WrongConstant")
    public void createIncomingCallNotification(ReactApplicationContext context,
                                               CallInvite callInvite,
                                               int notificationId,
                                               Intent launchIntent) {
        if (BuildConfig.DEBUG) {
            Log.d(TwilioVoiceModule.TAG, "createIncomingCallNotification intent " + launchIntent.getFlags());
        }
        PendingIntent pendingIntent = PendingIntent.getActivity(context, 0, launchIntent, PendingIntent.FLAG_UPDATE_CURRENT);

        NotificationManager notificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);

        /*
         * Pass the notification id and call sid to use as an identifier to cancel the
         * notification later
         */
        Bundle extras = new Bundle();
        extras.putInt(TwilioVoiceModule.INCOMING_CALL_NOTIFICATION_ID, notificationId);
        extras.putString(TwilioVoiceModule.CALL_SID_KEY, callInvite.getCallSid());
        extras.putString(TwilioVoiceModule.NOTIFICATION_TYPE, TwilioVoiceModule.ACTION_INCOMING_CALL);
        /*
         * Create the notification shown in the notification drawer
         */
        initIncomingCallChannel(notificationManager);

        NotificationCompat.Builder notificationBuilder =
                new NotificationCompat.Builder(context)
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                        .setCategory(NotificationCompat.CATEGORY_CALL)
                        .setSmallIcon(R.drawable.ic_call_white_24dp)
                        .setContentTitle("Incoming call")
                        .setContentText(callInvite.getFrom() + " is calling")
                        .setOngoing(true)
                        .setAutoCancel(true)
                        .setExtras(extras)
                        .setFullScreenIntent(pendingIntent, true);

        // build notification large icon
        Resources res = context.getResources();
        int largeIconResId = res.getIdentifier("ic_launcher", "mipmap", context.getPackageName());
        Bitmap largeIconBitmap = BitmapFactory.decodeResource(res, largeIconResId);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            if (largeIconResId != 0) {
                notificationBuilder.setLargeIcon(largeIconBitmap);
            }
        }

        // Reject action
        Intent rejectIntent = new Intent(TwilioVoiceModule.ACTION_REJECT_CALL)
                .putExtra(TwilioVoiceModule.INCOMING_CALL_NOTIFICATION_ID, notificationId)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pendingRejectIntent = PendingIntent.getBroadcast(context, 1, rejectIntent,
                PendingIntent.FLAG_UPDATE_CURRENT);
        notificationBuilder.addAction(0, "DISMISS", pendingRejectIntent);

        // Answer action
        Intent answerIntent = new Intent(TwilioVoiceModule.ACTION_ANSWER_CALL);
        answerIntent
                .putExtra(TwilioVoiceModule.INCOMING_CALL_NOTIFICATION_ID, notificationId)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pendingAnswerIntent = PendingIntent.getBroadcast(context, 0, answerIntent,
                PendingIntent.FLAG_UPDATE_CURRENT);
        notificationBuilder.addAction(R.drawable.ic_call_white_24dp, "ANSWER", pendingAnswerIntent);

        notificationManager.notify(notificationId, notificationBuilder.build());
        TwilioVoiceModule.callNotificationMap.put(TwilioVoiceModule.INCOMING_NOTIFICATION_PREFIX + callInvite.getCallSid(), notificationId);
    }

    public void initIncomingCallChannel(NotificationManager notificationManager) {
        if (Build.VERSION.SDK_INT < 26) {
            return;
        } else {
//            NotificationChannel channel = new NotificationChannel(VOICE_CHANNEL,
//                    "Primary Voice Channel", NotificationManager.IMPORTANCE_DEFAULT);
//            channel.setLightColor(Color.GREEN);
//            channel.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
//            notificationManager.createNotificationChannel(channel);
        }
    }

    public void createMissedCallNotification(ReactApplicationContext context, CallInvite callInvite) {
        SharedPreferences sharedPref = context.getSharedPreferences(TwilioVoiceModule.PREFERENCE_KEY, Context.MODE_PRIVATE);
        SharedPreferences.Editor sharedPrefEditor = sharedPref.edit();

        /*
         * Create a PendingIntent to specify the action when the notification is
         * selected in the notification drawer
         */
        Intent intent = new Intent(context, getMainActivityClass(context));
        intent.setAction(TwilioVoiceModule.ACTION_MISSED_CALL)
                .putExtra(TwilioVoiceModule.INCOMING_CALL_NOTIFICATION_ID, TwilioVoiceModule.MISSED_CALLS_NOTIFICATION_ID)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pendingIntent = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT);

        Intent clearMissedCallsCountIntent = new Intent(TwilioVoiceModule.ACTION_CLEAR_MISSED_CALLS_COUNT)
                .putExtra(TwilioVoiceModule.INCOMING_CALL_NOTIFICATION_ID, TwilioVoiceModule.CLEAR_MISSED_CALLS_NOTIFICATION_ID);
        PendingIntent clearMissedCallsCountPendingIntent = PendingIntent.getBroadcast(context, 0, clearMissedCallsCountIntent, 0);
        /*
         * Pass the notification id and call sid to use as an identifier to open the notification
         */
        Bundle extras = new Bundle();
        extras.putInt(TwilioVoiceModule.INCOMING_CALL_NOTIFICATION_ID, TwilioVoiceModule.MISSED_CALLS_NOTIFICATION_ID);
        extras.putString(TwilioVoiceModule.CALL_SID_KEY, callInvite.getCallSid());
        extras.putString(TwilioVoiceModule.NOTIFICATION_TYPE, TwilioVoiceModule.ACTION_MISSED_CALL);

        /*
         * Create the notification shown in the notification drawer
         */
        NotificationCompat.Builder notification =
                new NotificationCompat.Builder(context/*, VOICE_CHANNEL*/)
                        .setGroup(TwilioVoiceModule.MISSED_CALLS_GROUP)
                        .setGroupSummary(true)
                        .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                        .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                        .setSmallIcon(R.drawable.ic_call_missed_white_24dp)
                        .setContentTitle("Missed call")
                        .setContentText(callInvite.getFrom() + " called")
                        .setAutoCancel(true)
                        .setShowWhen(true)
                        .setExtras(extras)
                        .setDeleteIntent(clearMissedCallsCountPendingIntent)
                        .setContentIntent(pendingIntent);

        int missedCalls = sharedPref.getInt(TwilioVoiceModule.MISSED_CALLS_GROUP, 0);
        missedCalls++;
        if (missedCalls == 1) {
            inboxStyle = new NotificationCompat.InboxStyle();
            inboxStyle.setBigContentTitle("Missed call");
        } else {
            inboxStyle.setBigContentTitle(String.valueOf(missedCalls) + " missed calls");
        }
        inboxStyle.addLine("from: " + callInvite.getFrom());
        sharedPrefEditor.putInt(TwilioVoiceModule.MISSED_CALLS_GROUP, missedCalls);
        sharedPrefEditor.commit();

        notification.setStyle(inboxStyle);

        // build notification large icon
        Resources res = context.getResources();
        int largeIconResId = res.getIdentifier("ic_launcher", "mipmap", context.getPackageName());
        Bitmap largeIconBitmap = BitmapFactory.decodeResource(res, largeIconResId);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && largeIconResId != 0) {
            notification.setLargeIcon(largeIconBitmap);
        }

        NotificationManager notificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        notificationManager.notify(TwilioVoiceModule.MISSED_CALLS_NOTIFICATION_ID, notification.build());
    }

    public void createHangupLocalNotification(ReactApplicationContext context, String callSid, String caller) {
        PendingIntent pendingHangupIntent = PendingIntent.getBroadcast(
                context,
                0,
                new Intent(TwilioVoiceModule.ACTION_HANGUP_CALL).putExtra(TwilioVoiceModule.INCOMING_CALL_NOTIFICATION_ID, TwilioVoiceModule.HANGUP_NOTIFICATION_ID),
                PendingIntent.FLAG_UPDATE_CURRENT
        );
        Intent launchIntent = new Intent(context, getMainActivityClass(context));
        launchIntent.setAction(TwilioVoiceModule.ACTION_INCOMING_CALL)
                .putExtra(TwilioVoiceModule.INCOMING_CALL_NOTIFICATION_ID, TwilioVoiceModule.HANGUP_NOTIFICATION_ID)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

        PendingIntent activityPendingIntent = PendingIntent.getActivity(context, 0, launchIntent, PendingIntent.FLAG_UPDATE_CURRENT);

        /*
         * Pass the notification id and call sid to use as an identifier to cancel the
         * notification later
         */
        Bundle extras = new Bundle();
        extras.putInt(TwilioVoiceModule.INCOMING_CALL_NOTIFICATION_ID, TwilioVoiceModule.HANGUP_NOTIFICATION_ID);
        extras.putString(TwilioVoiceModule.CALL_SID_KEY, callSid);
        extras.putString(TwilioVoiceModule.NOTIFICATION_TYPE, TwilioVoiceModule.ACTION_HANGUP_CALL);

        NotificationCompat.Builder notification = new NotificationCompat.Builder(context/*, VOICE_CHANNEL*/)
                .setContentTitle("Call in progress")
                .setContentText(caller)
                .setSmallIcon(R.drawable.ic_call_white_24dp)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setOngoing(true)
                .setUsesChronometer(true)
                .setExtras(extras)
                .setContentIntent(activityPendingIntent);

        notification.addAction(0, "HANG UP", pendingHangupIntent);
        NotificationManager notificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        notificationManager.notify(TwilioVoiceModule.HANGUP_NOTIFICATION_ID, notification.build());
    }

    public void removeIncomingCallNotification(ReactApplicationContext context,
                                               CallInvite callInvite,
                                               int notificationId) {
        Log.d(TwilioVoiceModule.TAG, "removeIncomingCallNotification");
        NotificationManager notificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (callInvite != null && callInvite.getState() == CallInvite.State.PENDING) {
                /*
                 * If the incoming call message was cancelled then remove the notification by matching
                 * it with the call sid from the list of notifications in the notification drawer.
                 */
                StatusBarNotification[] activeNotifications = notificationManager.getActiveNotifications();
                for (StatusBarNotification statusBarNotification : activeNotifications) {
                    Notification notification = statusBarNotification.getNotification();
                    String notificationType = notification.extras.getString(TwilioVoiceModule.NOTIFICATION_TYPE);
                    if (callInvite.getCallSid().equals(notification.extras.getString(TwilioVoiceModule.CALL_SID_KEY)) &&
                            notificationType != null && notificationType.equals(TwilioVoiceModule.ACTION_INCOMING_CALL)) {
                        notificationManager.cancel(notification.extras.getInt(TwilioVoiceModule.INCOMING_CALL_NOTIFICATION_ID));
                    }
                }
            } else if (notificationId != 0) {
                notificationManager.cancel(notificationId);
            }
        } else {
            if (notificationId != 0) {
                notificationManager.cancel(notificationId);
            } else if (callInvite != null) {
                String notificationKey = TwilioVoiceModule.INCOMING_NOTIFICATION_PREFIX + callInvite.getCallSid();
                if (TwilioVoiceModule.callNotificationMap.containsKey(notificationKey)) {
                    notificationId = TwilioVoiceModule.callNotificationMap.get(notificationKey);
                    notificationManager.cancel(notificationId);
                    TwilioVoiceModule.callNotificationMap.remove(notificationKey);
                }
            }
        }
    }

    public void removeHangupNotification(ReactApplicationContext context) {
        NotificationManager notificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        notificationManager.cancel(TwilioVoiceModule.HANGUP_NOTIFICATION_ID);
    }
}