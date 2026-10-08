import { unstable_cache } from "next/cache";
import { cacheLife } from "next/cache";

// Slow data access: real network I/O, wrapped in unstable_cache.
const getData = unstable_cache(
  async () => {
    const res = await fetch("https://example.com/", { cache: "no-store" });
    await res.text();
    console.log("[repro] loader ran", new Date().toISOString());
    return { at: new Date().toISOString() };
  },
  ["data"],
  { revalidate: 60 },
);

// Gives the route a short expire (300 s; shorter would make it a dynamic hole).
async function Lifetime() {
  "use cache";
  cacheLife({ stale: 30, revalidate: 60, expire: 300 });
  return null;
}

export default async function Page() {
  const data = await getData();
  return (
    <main>
      <Lifetime />
      <p>data generated at {data.at}</p>
    </main>
  );
}
