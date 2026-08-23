/**
 * Shared Australian BAS/PAYG tax logic.
 *
 * Plain browser script — no bundler, no npm install, no build step. Include
 * it with a normal <script src="src/utils/taxEngine.js"></script> tag
 * BEFORE any code that reads window.TaxEngine, exactly like the Tailwind
 * and Supabase CDN <script> tags already in index.html.
 *
 * This file is shared, byte-for-byte, between Joe's Handyman and PK
 * Woodworking so both apps compute the financial year boundary and the
 * rolling PAYG estimate the same way. The functions below only take plain
 * arrays/numbers in and return plain objects/numbers out — they don't know
 * about Supabase, React, or either app's table shape, so each app is
 * responsible for mapping its own rows into the shapes documented below
 * before calling in.
 */
(function (global) {
  'use strict';

  var TAX_RATE = 0.22;

  /**
   * Australian financial year: 1 July - 30 June.
   * @param {Date} [referenceDate] - defaults to now.
   * @returns {{ label: string, start: Date, end: Date }}
   *   label is e.g. "2025-2026" for the year starting 1 July 2025.
   */
  function getAustralianFinancialYear(referenceDate) {
    var ref = referenceDate instanceof Date && !isNaN(referenceDate.getTime())
      ? referenceDate
      : new Date();
    // getMonth() is 0-indexed, so 6 = July.
    var startYear = ref.getMonth() >= 6 ? ref.getFullYear() : ref.getFullYear() - 1;
    return {
      label: startYear + '-' + (startYear + 1),
      start: new Date(startYear, 6, 1, 0, 0, 0, 0),
      end: new Date(startYear + 1, 5, 30, 23, 59, 59, 999),
    };
  }

  /**
   * Rolling PAYG/BAS estimate: 22% of every income entry dated STRICTLY
   * AFTER the most recent payment_date found in taxPayments (or since the
   * beginning of time if no payment has ever been logged). Logging a
   * payment therefore "resets" this to zero going forward.
   *
   * Only invoices with status === 'Paid' count as realised income, the
   * same convention the Financial Overview tab already uses for its
   * income figures.
   *
   * @param {Array<{total_amount:number, status:string, created_at:string}>} invoices
   * @param {Array<{amount:number, date:string}>} manualIncome
   * @param {Array<{payment_date:string, amount:number}>} taxPayments
   * @returns {{ sinceDate: Date, rollingIncome: number, basDue: number, entryCount: number }}
   */
  function calculateRollingPAYGBas(invoices, manualIncome, taxPayments) {
    var paymentDates = (taxPayments || [])
      .map(function (p) { return new Date(p.payment_date); })
      .filter(function (d) { return !isNaN(d.getTime()); });

    var sinceDate = paymentDates.length
      ? new Date(Math.max.apply(null, paymentDates.map(function (d) { return d.getTime(); })))
      : new Date(0);

    var rollingIncome = 0;
    var entryCount = 0;

    (invoices || []).forEach(function (inv) {
      if (inv.status !== 'Paid') return;
      var invDate = new Date(inv.created_at);
      if (!isNaN(invDate.getTime()) && invDate > sinceDate) {
        rollingIncome += Number(inv.total_amount || 0);
        entryCount += 1;
      }
    });

    (manualIncome || []).forEach(function (row) {
      var rowDate = new Date(row.date);
      if (!isNaN(rowDate.getTime()) && rowDate > sinceDate) {
        rollingIncome += Number(row.amount || 0);
        entryCount += 1;
      }
    });

    return {
      sinceDate: sinceDate,
      rollingIncome: rollingIncome,
      basDue: rollingIncome * TAX_RATE,
      entryCount: entryCount,
    };
  }

  /**
   * Sums taxPayments.amount for every row whose financial_year matches the
   * given (or current) financial year label, e.g. "2025-2026".
   * @param {Array<{financial_year:string, amount:number}>} taxPayments
   * @param {string} [financialYearLabel] - defaults to the active FY.
   * @returns {number}
   */
  function calculateTotalTaxPaidYTD(taxPayments, financialYearLabel) {
    var label = financialYearLabel || getAustralianFinancialYear().label;
    return (taxPayments || [])
      .filter(function (p) { return p.financial_year === label; })
      .reduce(function (sum, p) { return sum + Number(p.amount || 0); }, 0);
  }

  global.TaxEngine = {
    TAX_RATE: TAX_RATE,
    getAustralianFinancialYear: getAustralianFinancialYear,
    calculateRollingPAYGBas: calculateRollingPAYGBas,
    calculateTotalTaxPaidYTD: calculateTotalTaxPaidYTD,
  };
})(window);
