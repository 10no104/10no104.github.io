// 버튼 클릭 시 해당 섹션으로 스크롤
document.querySelectorAll('.navBtn').forEach(btn => {
  btn.addEventListener('click', () => {
    const targetId = btn.getAttribute('data-target');
    const targetEl = document.getElementById(targetId);
    targetEl.scrollIntoView({ behavior: 'smooth' });
  });
});
