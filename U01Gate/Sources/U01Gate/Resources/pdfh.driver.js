// C-5 用的真实 pdfh/pdfa/pd 实现（JS 侧，基于 cheerio）。
// 语义对齐 drpy 宿主环境（APK assets 内置 QuickJS 桥提供同签名函数）：
//   pdfh(html, rule) —— rule 为 `选择器&&选择器&&…&&Text|Html|属性名` 的链式下钻
//   pd(html, rule, baseUrl) —— pdfh 结果为相对地址时按 baseUrl 拼接
//   pdfa(html, rule) —— 返回匹配列表（数组）
// 覆盖 ：eq(n)（0 基）、属性选择器、|| 并列候选。
globalThis.pdfh = function (html, rule) {
  if (!html || !rule) return '';
  var steps = String(rule).split('&&');
  var scope = cheerio.load('<div id="__pdfh_root">' + html + '</div>');
  var node = scope.root().find('#__pdfh_root');
  for (var i = 0; i < steps.length; i++) {
    var step = steps[i].trim();
    if (!step) continue;
    if (i === steps.length - 1) {
      if (step === 'Text') return node.text().trim();
      if (step === 'Html') return node.html() || '';
      var attr = node.attr(step);
      return attr === undefined ? '' : attr;
    }
    // || 并列候选：任一命中即采用
    var alts = step.split('||');
    var found = null;
    for (var j = 0; j < alts.length; j++) {
      var hit = node.find(alts[j].trim());
      if (hit && hit.length > 0) { found = hit; break; }
    }
    if (!found) return '';
    node = found.first();
  }
  return node.text().trim();
};

globalThis.pdfa = function (html, rule) {
  if (!html || !rule) return [];
  var parts = String(rule).split('&&');
  var last = parts.pop().trim();
  var scope = cheerio.load('<div id="__pdfh_root">' + html + '</div>');
  var node = scope.root().find('#__pdfh_root');
  for (var i = 0; i < parts.length; i++) {
    var step = parts[i].trim();
    if (!step) continue;
    var hit = node.find(step);
    if (!hit || hit.length === 0) return [];
    node = hit.first();
  }
  var items = node.find(last);
  var out = [];
  items.each(function (_, el) {
    out.push(scope.html(el));
  });
  return out;
};

globalThis.pd = function (html, rule, baseUrl) {
  var value = globalThis.pdfh(html, rule);
  if (!value) return '';
  if (/^https?:\\/\\//i.test(value)) return value;
  if (!baseUrl) return value;
  if (value.indexOf('//') === 0) return 'https:' + value;
  var base = String(baseUrl);
  if (base.indexOf('/') === base.length - 1) base = base.slice(0, -1);
  if (value.charAt(0) === '/') return base + value;
  return base + '/' + value;
};
