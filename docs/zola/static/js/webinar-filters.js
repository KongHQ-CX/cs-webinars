// Client-side filtering for the webinars gallery.
//
// All cards render into one page, so filtering is just showing and hiding
// them. Three independent dimensions, combined with AND:
//   - search: substring match over each card's visible text
//   - tags: OR across the selected tag chips (none selected = all). Tags are a
//     single pool mixing products (Konnect, Gateway…) with themes (Security…).
//   - year: exact match on the card's year (empty = all)
//
// The filter bar ships with a `hidden` attribute and is revealed here, so a
// browser with JS disabled just sees the full, unfiltered list.
(function () {
  "use strict";

  var root = document.querySelector("[data-webinar-filters]");
  var grid = document.querySelector("[data-webinar-grid]");
  if (!root || !grid) {
    return;
  }

  var cards = Array.prototype.slice.call(grid.querySelectorAll(".card"));
  var searchInput = root.querySelector("[data-filter-search]");
  var yearSelect = root.querySelector("[data-filter-year]");
  var tagButtons = Array.prototype.slice.call(
    root.querySelectorAll("[data-filter-tag]")
  );
  var statusEl = root.querySelector("[data-filter-status]");
  var emptyEl = document.querySelector("[data-filter-empty]");

  // Precompute each card's searchable text and tag set once.
  var index = cards.map(function (card) {
    var tags = (card.getAttribute("data-tags") || "")
      .split(/\s+/)
      .filter(Boolean);
    return {
      card: card,
      text: (card.textContent || "").toLowerCase(),
      tags: tags,
      year: card.getAttribute("data-year") || "",
    };
  });

  var state = { search: "", tags: [], year: "" };

  // Called on the first user interaction; stops cards re-running their entry
  // animation each time they are re-shown.
  function markFiltering() {
    grid.classList.add("is-filtering");
  }

  function matches(entry) {
    if (state.search && entry.text.indexOf(state.search) === -1) {
      return false;
    }
    if (state.year && entry.year !== state.year) {
      return false;
    }
    if (state.tags.length) {
      var hit = state.tags.some(function (t) {
        return entry.tags.indexOf(t) !== -1;
      });
      if (!hit) {
        return false;
      }
    }
    return true;
  }

  function apply() {
    var visible = 0;
    index.forEach(function (entry) {
      var show = matches(entry);
      entry.card.hidden = !show;
      if (show) {
        visible += 1;
      }
    });

    if (emptyEl) {
      emptyEl.hidden = visible !== 0;
    }

    if (statusEl) {
      var total = index.length;
      var filtered = state.search || state.year || state.tags.length;
      statusEl.textContent = filtered
        ? "Showing " + visible + " of " + total
        : "";
    }
  }

  if (searchInput) {
    searchInput.addEventListener("input", function () {
      markFiltering();
      state.search = searchInput.value.trim().toLowerCase();
      apply();
    });
  }

  if (yearSelect) {
    yearSelect.addEventListener("change", function () {
      markFiltering();
      state.year = yearSelect.value;
      apply();
    });
  }

  tagButtons.forEach(function (btn) {
    btn.addEventListener("click", function () {
      markFiltering();
      var value = btn.getAttribute("data-filter-tag");

      if (value === "") {
        // "All" clears every tag selection.
        state.tags = [];
      } else {
        var i = state.tags.indexOf(value);
        if (i === -1) {
          state.tags.push(value);
        } else {
          state.tags.splice(i, 1);
        }
      }

      // Reflect state on the chips: "All" is active only when nothing else is.
      tagButtons.forEach(function (b) {
        var v = b.getAttribute("data-filter-tag");
        var active =
          v === ""
            ? state.tags.length === 0
            : state.tags.indexOf(v) !== -1;
        b.classList.toggle("chip--active", active);
        b.setAttribute("aria-pressed", active ? "true" : "false");
      });

      apply();
    });
  });

  // JS is running, so show the controls and do an initial pass.
  root.hidden = false;
  apply();
})();
