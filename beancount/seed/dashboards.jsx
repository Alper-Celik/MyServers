// Starter dashboard config for fava-dashboards, seeded once into /var/lib/fava
// next to the ledger (the extension picks up dashboards.{tsx,ts,jsx,js} by name
// from the ledger's directory, so keep the filename). Charts are ECharts
// options; the available fields are documented in fava-dashboards' README.
import { defineConfig } from "fava-dashboards";

const currency = {
  name: "currency",
  label: "Currency",
  options: async ({ ledger }) => ledger.operatingCurrencies,
};

const sumOf = async (ledger, ccy, accounts, negate) => {
  const rows = await ledger.query(
    `SELECT year, month, CONVERT(SUM(position), '${ccy}') AS value
     WHERE account ~ '${accounts}'
     GROUP BY year, month
     ORDER BY year, month`,
  );
  return rows.map((row) => ({ date: `${row.year}-${row.month}`, value: (negate ? -1 : 1) * row.value[ccy] }));
};

export default defineConfig({
  dashboards: [
    {
      name: "Overview",
      variables: [currency],
      panels: [
        {
          title: "Net worth",
          width: "50%",
          height: "320px",
          kind: "echarts",
          spec: async ({ ledger, variables }) => {
            const rows = await ledger.query(
              `SELECT year, month, CONVERT(SUM(position), '${variables.currency}') AS value
               WHERE account ~ '^(Assets|Liabilities):'
               GROUP BY year, month
               ORDER BY year, month`,
            );
            let running = 0;
            const data = rows.map((row) => [row.year + "-" + row.month, (running += row.value[variables.currency])]);
            return {
              tooltip: { trigger: "axis" },
              xAxis: { type: "category", data: data.map(([month]) => month) },
              yAxis: { type: "value" },
              series: [{ type: "line", smooth: true, areaStyle: {}, data: data.map(([, value]) => value) }],
            };
          },
        },
        {
          title: "Monthly balance change",
          width: "50%",
          height: "320px",
          kind: "echarts",
          spec: async ({ ledger, variables }) => {
            const [income, expenses] = await Promise.all([
              sumOf(ledger, variables.currency, "^Income:", true),
              sumOf(ledger, variables.currency, "^Expenses:", false),
            ]);
            const months = [...new Set([...income, ...expenses].map((row) => row.date))].sort();
            const pick = (rows) => months.map((month) => rows.find((row) => row.date === month)?.value ?? 0);
            return {
              tooltip: { trigger: "axis" },
              legend: { data: ["Income", "Expenses"] },
              xAxis: { type: "category", data: months },
              yAxis: { type: "value" },
              series: [
                { name: "Income", type: "bar", data: pick(income) },
                { name: "Expenses", type: "bar", data: pick(expenses) },
              ],
            };
          },
        },
        {
          title: "Where the money went",
          width: "100%",
          height: "360px",
          kind: "echarts",
          spec: async ({ ledger, variables }) => {
            const rows = await ledger.query(
              `SELECT account, CONVERT(SUM(position), '${variables.currency}') AS value
               WHERE account ~ '^Expenses:'
               GROUP BY account
               ORDER BY value DESC
               LIMIT 12`,
            );
            return {
              tooltip: { trigger: "item" },
              series: [
                {
                  type: "pie",
                  radius: ["40%", "70%"],
                  data: rows.map((row) => ({ name: row.account, value: row.value[variables.currency] })),
                },
              ],
            };
          },
        },
      ],
    },
  ],
});
