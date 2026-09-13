package com.greighstudios.voteaxis

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class IssueWidgetProvider : HomeWidgetProvider() {
  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { widgetId ->
      val views = RemoteViews(context.packageName, R.layout.issue_widget)
      val headline = widgetData.getString("headline", null) ?: "Issue of the day"
      val question =
          widgetData.getString("question", null)
              ?: "Open Voteaxis to take the quiz."
      val status = widgetData.getString("status", "needQuiz") ?: "needQuiz"
      val axisLabel = widgetData.getString("axisLabel", "") ?: ""
      val hasProfile = widgetData.getString("hasProfile", "0") == "1"

      views.setTextViewText(R.id.widget_headline, headline.uppercase())
      views.setTextViewText(R.id.widget_question, question)

      val openApp =
          HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
      views.setOnClickPendingIntent(R.id.widget_container, openApp)

      when {
        !hasProfile || status == "needQuiz" -> {
          views.setViewVisibility(R.id.widget_actions, View.GONE)
          views.setViewVisibility(R.id.widget_status, View.VISIBLE)
          views.setTextViewText(R.id.widget_status, "Open Voteaxis to take the quiz")
        }
        status == "saved" -> {
          views.setViewVisibility(R.id.widget_actions, View.GONE)
          views.setViewVisibility(R.id.widget_status, View.VISIBLE)
          val saved =
              if (axisLabel.isEmpty()) "Saved for today"
              else "Saved · $axisLabel"
          views.setTextViewText(R.id.widget_status, saved)
        }
        else -> {
          views.setViewVisibility(R.id.widget_actions, View.VISIBLE)
          views.setViewVisibility(R.id.widget_status, View.GONE)
          views.setOnClickPendingIntent(
              R.id.widget_disagree,
              HomeWidgetBackgroundIntent.getBroadcast(
                  context,
                  Uri.parse("voteaxis://calibrate?side=disagree"),
              ),
          )
          views.setOnClickPendingIntent(
              R.id.widget_agree,
              HomeWidgetBackgroundIntent.getBroadcast(
                  context,
                  Uri.parse("voteaxis://calibrate?side=agree"),
              ),
          )
        }
      }

      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
