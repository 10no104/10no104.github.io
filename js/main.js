// 예: 버튼 클릭 시 스크롤 이동
document.querySelectorAll('.navBtn').forEach(btn => {
  btn.addEventListener('click', () => {
    const targetId = btn.getAttribute('data-target');
    const targetEl = document.getElementById(targetId);
    targetEl.scrollIntoView({ behavior: 'smooth' });
  });
});
