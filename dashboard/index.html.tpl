<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Lily Pad Dashboard</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js"></script>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #f8fafc;
      color: #1e293b;
      padding: 1.5rem;
      max-width: 900px;
      margin: 0 auto;
    }
    header { margin-bottom: 2rem; }
    .hero {
      width: 100%;
      max-height: 360px;
      object-fit: cover;
      object-position: center top;
      border-radius: 16px;
      box-shadow: 0 4px 20px rgba(0,0,0,0.15);
      display: block;
      margin-bottom: 1.25rem;
    }
    header h1 { font-size: 1.75rem; font-weight: 700; margin-bottom: 0.25rem; }
    header .subtitle { color: #64748b; font-size: 0.9rem; }
    h1 { font-size: 1.75rem; font-weight: 700; margin-bottom: 0.25rem; }
    .subtitle { color: #64748b; font-size: 0.9rem; margin-bottom: 2rem; }
    h2 { font-size: 1.1rem; font-weight: 600; margin-bottom: 1rem; color: #334155; }
    section { margin-bottom: 2.5rem; }

    /* Summary cards */
    .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 1rem; }
    .card {
      background: #fff;
      border-radius: 12px;
      padding: 1.25rem;
      box-shadow: 0 1px 4px rgba(0,0,0,0.08);
      border-top: 4px solid #e2e8f0;
    }
    .card.pee   { border-top-color: #fbbf24; }
    .card.poop  { border-top-color: #92400e; }
    .card.vomit { border-top-color: #f97316; }
    .card.ate_ground { border-top-color: #65a30d; }
    .card.walk       { border-top-color: #3b82f6; }
    .card-label { font-size: 0.8rem; color: #64748b; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.4rem; }
    .card-count { font-size: 2.25rem; font-weight: 700; line-height: 1; }
    .card-detail { font-size: 0.78rem; color: #94a3b8; margin-top: 0.3rem; }

    /* Feed */
    .feed { display: flex; flex-direction: column; gap: 0.5rem; }
    .feed-item {
      background: #fff;
      border-radius: 8px;
      padding: 0.75rem 1rem;
      display: flex;
      align-items: center;
      gap: 0.75rem;
      box-shadow: 0 1px 3px rgba(0,0,0,0.06);
      border-left: 4px solid #e2e8f0;
    }
    .feed-item.pee        { border-left-color: #fbbf24; }
    .feed-item.poop       { border-left-color: #92400e; }
    .feed-item.vomit      { border-left-color: #f97316; }
    .feed-item.ate_ground { border-left-color: #65a30d; }
    .feed-item.note       { border-left-color: #6366f1; }
    .feed-item.walk       { border-left-color: #3b82f6; }
    .feed-type { font-weight: 600; font-size: 0.9rem; min-width: 80px; }
    .feed-attr { color: #64748b; font-size: 0.85rem; flex: 1; }
    .feed-time { color: #94a3b8; font-size: 0.8rem; white-space: nowrap; }

    /* Charts */
    .charts { display: grid; grid-template-columns: 1fr 1fr; gap: 1.5rem; }
    @media (max-width: 600px) { .charts { grid-template-columns: 1fr; } }
    .chart-box {
      background: #fff;
      border-radius: 12px;
      padding: 1.25rem;
      box-shadow: 0 1px 4px rgba(0,0,0,0.08);
    }
    .chart-box h2 { margin-bottom: 0.75rem; }

    /* Show More button */
    .show-more-btn {
      margin-top: 0.75rem;
      padding: 0.5rem 1.25rem;
      background: #f1f5f9;
      border: 1px solid #e2e8f0;
      border-radius: 8px;
      font-size: 0.85rem;
      color: #475569;
      cursor: pointer;
    }
    .show-more-btn:hover { background: #e2e8f0; }

    /* Notes */
    .notes-list { display: flex; flex-direction: column; gap: 0.5rem; }
    .note-item {
      background: #fff;
      border-radius: 8px;
      padding: 0.75rem 1rem;
      border-left: 4px solid #6366f1;
      box-shadow: 0 1px 3px rgba(0,0,0,0.06);
    }
    .note-text { font-size: 0.9rem; margin-bottom: 0.25rem; }
    .note-time { font-size: 0.78rem; color: #94a3b8; }

    /* Loading / error */
    .status { color: #64748b; font-style: italic; }
    .error  { color: #ef4444; }
  </style>
</head>
<body>

<header>
  <img src="Lily-and-DC.PNG" alt="Lily and DC" class="hero" />
  <h1>Lily Pad</h1>
  <p class="subtitle" id="generated-at">Loading&hellip;</p>
</header>

<section id="summary-section">
  <h2>Today's Summary</h2>
  <div class="cards" id="summary-cards">
    <p class="status">Loading&hellip;</p>
  </div>
</section>

<section id="walk-section">
  <h2>Minutes Walked (14 days)</h2>
  <div class="chart-box">
    <canvas id="walk-chart" height="160"></canvas>
  </div>
</section>

<section id="charts-section">
  <h2>14-Day Activity</h2>
  <div class="chart-box">
    <canvas id="activity-chart" height="160"></canvas>
  </div>
</section>

<section id="poop-section">
  <h2>Poop Quality (30 days)</h2>
  <div style="max-width: 320px;">
    <div class="chart-box">
      <canvas id="poop-chart" height="220"></canvas>
    </div>
  </div>
</section>

<section id="notes-section">
  <h2>Notes</h2>
  <div class="notes-list" id="notes-list">
    <p class="status">Loading&hellip;</p>
  </div>
</section>

<section id="feed-section">
  <h2>Recent Activity</h2>
  <div class="feed" id="feed">
    <p class="status">Loading&hellip;</p>
  </div>
  <button class="show-more-btn" id="feed-more" style="display:none">Show More</button>
</section>

<script>
  var API_URL = "${api_url}";

  var TYPE_LABELS = {
    pee:        "Pee",
    poop:       "Poop",
    vomit:      "Vomit",
    ate_ground: "Ate Off Ground",
    note:       "Note",
    walk:       "Walk"
  };

  var TYPE_COLORS = {
    pee:        "#fbbf24",
    poop:       "#92400e",
    vomit:      "#f97316",
    ate_ground: "#65a30d",
    note:       "#6366f1",
    walk:       "#3b82f6"
  };

  function pacificMidnightISO(daysAgo) {
    var d = new Date();
    d.setDate(d.getDate() - (daysAgo || 0));
    var s = d.toLocaleString("en-US", { timeZone: "America/Los_Angeles" });
    var pd = new Date(s);
    pd.setHours(0, 0, 0, 0);
    return pd.toISOString();
  }

  function formatTS(iso) {
    var d = new Date(iso);
    var opts = { timeZone: "America/Los_Angeles", month: "short", day: "numeric",
                 hour: "numeric", minute: "2-digit" };
    return d.toLocaleString("en-US", opts);
  }

  function todayPacificLabel() {
    var d = new Date();
    var s = d.toLocaleString("en-US", { timeZone: "America/Los_Angeles",
                                         month: "short", day: "numeric" });
    return s;
  }

  function dayLabelPacific(daysAgo) {
    var d = new Date();
    d.setDate(d.getDate() - daysAgo);
    return d.toLocaleString("en-US", { timeZone: "America/Los_Angeles",
                                        month: "short", day: "numeric" });
  }

  function isAfterMidnightPacific(iso, daysAgo) {
    return iso >= pacificMidnightISO(daysAgo);
  }

  function isBeforeMidnightPacific(iso, daysAgo) {
    return daysAgo === 0 || iso < pacificMidnightISO(daysAgo - 1);
  }

  function timeSince(iso) {
    var diffMs = Date.now() - new Date(iso).getTime();
    var totalMin = Math.floor(diffMs / 60000);
    var days  = Math.floor(totalMin / 1440);
    var hours = Math.floor((totalMin % 1440) / 60);
    var mins  = totalMin % 60;
    function p(n, w) { return n + " " + w + (n !== 1 ? "s" : ""); }
    if (days  > 0) return p(days,  "day")  + " " + p(hours, "hour")   + " ago";
    if (hours > 0) return p(hours, "hour") + " " + p(mins,  "minute") + " ago";
    return p(mins, "minute") + " ago";
  }

  function renderSummary(events) {
    var todayCutoff = pacificMidnightISO(0);
    var todayEvents = events.filter(function(e) { return e.timestamp >= todayCutoff; });

    var types = ["pee", "poop", "vomit"];
    var html = "";
    types.forEach(function(t) {
      var typeEvents = todayEvents.filter(function(e) { return e.event_type === t; });
      var count = typeEvents.length;
      var detail = "";
      if (t === "poop" && count > 0) {
        var attrs = { normal: 0, soft: 0, diarrhea: 0 };
        typeEvents.forEach(function(e) {
          var a = e.attribute || "normal";
          if (attrs[a] !== undefined) attrs[a]++;
        });
        var parts = [];
        if (attrs.normal)   parts.push(attrs.normal + " normal");
        if (attrs.soft)     parts.push(attrs.soft + " soft");
        if (attrs.diarrhea) parts.push(attrs.diarrhea + " diarrhea");
        if (parts.length) detail = parts.join(", ");
      }
      var lastStr = "";
      if (t === "pee" || t === "poop") {
        var allOfType = events.filter(function(e) { return e.event_type === t; });
        if (allOfType.length) {
          lastStr = "last: " + timeSince(allOfType[0].timestamp);
        }
      }
      html += '<div class="card ' + t + '">' +
              '<div class="card-label">' + TYPE_LABELS[t] + '</div>' +
              '<div class="card-count">' + count + '</div>' +
              (detail  ? '<div class="card-detail">' + detail  + '</div>' : '') +
              (lastStr ? '<div class="card-detail">' + lastStr + '</div>' : '') +
              '</div>';
    });
    document.getElementById("summary-cards").innerHTML = html;
  }

  var allFeedEvents = [];
  var feedLimit = 50;

  function applyFeedLimit() {
    var visible = allFeedEvents.slice(0, feedLimit);
    var html = "";
    visible.forEach(function(e) {
      var attr = e.attribute || "";
      if (e.event_type === "walk" && attr) attr = attr + " min";
      var attrHtml = attr ? '<span class="feed-attr">' + attr + '</span>' : '<span class="feed-attr"></span>';
      if (e.event_type === "note") {
        attrHtml = '<span class="feed-attr">' + attr + '</span>';
      }
      html += '<div class="feed-item ' + e.event_type + '">' +
              '<span class="feed-type">' + (TYPE_LABELS[e.event_type] || e.event_type) + '</span>' +
              attrHtml +
              '<span class="feed-time">' + formatTS(e.timestamp) + '</span>' +
              '</div>';
    });
    document.getElementById("feed").innerHTML = html;
    document.getElementById("feed-more").style.display =
      feedLimit < allFeedEvents.length ? "inline-block" : "none";
  }

  function renderFeed(events) {
    allFeedEvents = events;
    feedLimit = 50;
    if (!allFeedEvents.length) {
      document.getElementById("feed").innerHTML = '<p class="status">No events found.</p>';
      return;
    }
    applyFeedLimit();
  }

  document.getElementById("feed-more").onclick = function() {
    feedLimit += 50;
    applyFeedLimit();
  };

  function renderActivityChart(events) {
    var labels = [];
    var peeData = [];
    var poopData = [];
    for (var i = 13; i >= 0; i--) {
      labels.push(dayLabelPacific(i));
      var start = pacificMidnightISO(i);
      var end = i > 0 ? pacificMidnightISO(i - 1) : new Date().toISOString();
      var dayEvents = events.filter(function(e) {
        return e.timestamp >= start && e.timestamp < end;
      });
      peeData.push(dayEvents.filter(function(e) { return e.event_type === "pee"; }).length);
      poopData.push(dayEvents.filter(function(e) { return e.event_type === "poop"; }).length);
    }
    var ctx = document.getElementById("activity-chart").getContext("2d");
    new Chart(ctx, {
      type: "bar",
      data: {
        labels: labels,
        datasets: [
          { label: "Pee",  data: peeData,  backgroundColor: "#fbbf24", stack: "a" },
          { label: "Poop", data: poopData, backgroundColor: "#92400e", stack: "a" }
        ]
      },
      options: {
        responsive: true,
        plugins: { legend: { position: "top" } },
        scales: {
          x: { stacked: true, ticks: { font: { size: 10 } } },
          y: { stacked: true, beginAtZero: true, ticks: { stepSize: 1 } }
        }
      }
    });
  }

  function renderPoopChart(events) {
    var poops = events.filter(function(e) { return e.event_type === "poop"; });
    var counts = { normal: 0, soft: 0, diarrhea: 0 };
    poops.forEach(function(e) {
      var a = e.attribute || "normal";
      if (counts[a] !== undefined) counts[a]++;
    });
    var ctx = document.getElementById("poop-chart").getContext("2d");
    new Chart(ctx, {
      type: "doughnut",
      data: {
        labels: ["Normal", "Soft", "Diarrhea"],
        datasets: [{
          data: [counts.normal, counts.soft, counts.diarrhea],
          backgroundColor: ["#22c55e", "#eab308", "#ef4444"],
          borderWidth: 2
        }]
      },
      options: {
        responsive: true,
        plugins: { legend: { position: "bottom" } }
      }
    });
  }

  function renderNotes(events) {
    var noteEvents = events.filter(function(e) { return e.event_type === "note"; });
    if (!noteEvents.length) {
      document.getElementById("notes-list").innerHTML = '<p class="status">No notes yet.</p>';
      return;
    }
    var html = "";
    noteEvents.forEach(function(e) {
      html += '<div class="note-item">' +
              '<div class="note-text">' + (e.attribute || "") + '</div>' +
              '<div class="note-time">' + formatTS(e.timestamp) + '</div>' +
              '</div>';
    });
    document.getElementById("notes-list").innerHTML = html;
  }

  function renderWalkChart(events) {
    var labels = [], data = [];
    for (var i = 13; i >= 0; i--) {
      labels.push(dayLabelPacific(i));
      var start = pacificMidnightISO(i);
      var end   = i > 0 ? pacificMidnightISO(i - 1) : new Date().toISOString();
      var mins  = events
        .filter(function(e) { return e.event_type === "walk" && e.timestamp >= start && e.timestamp < end; })
        .reduce(function(sum, e) { return sum + (parseInt(e.attribute) || 0); }, 0);
      data.push(mins);
    }
    var ctx = document.getElementById("walk-chart").getContext("2d");
    new Chart(ctx, {
      type: "bar",
      data: {
        labels: labels,
        datasets: [{ label: "Minutes", data: data, backgroundColor: "#3b82f6" }]
      },
      options: {
        responsive: true,
        plugins: { legend: { display: false } },
        scales: {
          x: { ticks: { font: { size: 10 } } },
          y: { beginAtZero: true, ticks: { stepSize: 10 } }
        }
      }
    });
  }

  function render(data) {
    var events = data.events || [];
    var generatedAt = data.generated_at
      ? "Last updated: " + formatTS(data.generated_at)
      : "";
    document.getElementById("generated-at").textContent = generatedAt;
    renderSummary(events);
    renderFeed(events);
    renderActivityChart(events);
    renderPoopChart(events);
    renderWalkChart(events);
    renderNotes(events);
  }

  async function loadData() {
    try {
      var resp = await fetch(API_URL);
      if (!resp.ok) throw new Error("HTTP " + resp.status);
      var data = await resp.json();
      render(data);
    } catch (err) {
      document.getElementById("generated-at").innerHTML =
        '<span class="error">Error loading data: ' + err.message + '</span>';
    }
  }

  loadData();
</script>
</body>
</html>
