(function () {
  "use strict";

  var mainVideo = document.getElementById("mainVideo");
  var mainSource = document.getElementById("mainVideoSource");
  var mainTitle = document.getElementById("mainVideoTitle");
  var mainMeta = document.getElementById("mainVideoMeta");
  var cardButtons = document.querySelectorAll(".video-card__button");

  function playVideo(button) {
    var src = button.getAttribute("data-video-src");
    var poster = button.getAttribute("data-video-poster");
    var title = button.getAttribute("data-video-title");
    var meta = button.getAttribute("data-video-meta");

    if (!src) return;

    // Swap the source and reload so the new video always plays in the big section
    mainSource.setAttribute("src", src);
    mainVideo.setAttribute("poster", poster || "");
    mainVideo.load();
    mainVideo.play().catch(function () {
      // Autoplay can be blocked (e.g. mobile browsers) — that's fine,
      // the poster + controls let the person hit play themselves.
    });

    mainTitle.textContent = title || "";
    mainMeta.textContent = meta || "";

    cardButtons.forEach(function (btn) {
      btn.classList.toggle("video-card--active", btn === button);
    });

    // Keep the player in view when picking a new video on mobile
    document.querySelector(".video-player").scrollIntoView({
      behavior: "smooth",
      block: "start"
    });
  }

  cardButtons.forEach(function (button) {
    button.addEventListener("click", function () {
      playVideo(button);
    });
  });
})();