// Client-side filtering for the webinars gallery.
//
// All cards render into one page, so filtering is just showing and hiding
// them. Three independent dimensions, combined with AND:
//   - search: substring match over each card's visible text
//   - products: OR across the selected product chips (none selected = all)
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
  var productButtons = Array.prototype.slice.call(
    root.querySelectorAll("[data-filter-product]")
  );
  var statusEl = root.querySelector("[data-filter-status]");
  var emptyEl = document.querySelector("[data-filter-empty]");

  // Precompute each card's searchable text and product set once.
  var index = cards.map(function (card) {
    var products = (card.getAttribute("data-products") || "")
      .split(/\s+/)
      .filter(Boolean);
    return {
      card: card,
      text: (card.textContent || "").toLowerCase(),
      products: products,
      year: card.getAttribute("data-year") || "",
    };
  });

  var state = { search: "", products: [], year: "" };

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
    if (state.products.length) {
      var hit = state.products.some(function (p) {
        return entry.products.indexOf(p) !== -1;
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
      var filtered =
        state.search || state.year || state.products.length;
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

  productButtons.forEach(function (btn) {
    btn.addEventListener("click", function () {
      markFiltering();
      var value = btn.getAttribute("data-filter-product");

      if (value === "") {
        // "All" clears every product selection.
        state.products = [];
      } else {
        var i = state.products.indexOf(value);
        if (i === -1) {
          state.products.push(value);
        } else {
          state.products.splice(i, 1);
        }
      }

      // Reflect state on the chips: "All" is active only when nothing else is.
      productButtons.forEach(function (b) {
        var v = b.getAttribute("data-filter-product");
        var active =
          v === ""
            ? state.products.length === 0
            : state.products.indexOf(v) !== -1;
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
