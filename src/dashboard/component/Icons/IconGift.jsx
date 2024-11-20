import React from 'react';

export default function IconGift({ fillColor = 'none', style = {}, ...props }) {
  return (
    <svg
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      style={style}
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M20 8H4C3.44772 8 3 8.44772 3 9V11C3 11.5523 3.44772 12 4 12H20C20.5523 12 21 11.5523 21 11V9C21 8.44772 20.5523 8 20 8Z"
        stroke={fillColor}
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d="M12 8V21"
        stroke={fillColor}
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d="M19 12V19C19 19.5304 18.7893 20.0391 18.4142 20.4142C18.0391 20.7893 17.5304 21 17 21H7C6.46957 21 5.96086 20.7893 5.58579 20.4142C5.21071 20.0391 5 19.5304 5 19V12"
        stroke={fillColor}
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        d="M7.5 7.99995C6.83696 7.99995 6.20107 7.73656 5.73223 7.26772C5.26339 6.79887 5 6.16299 5 5.49995C5 4.83691 5.26339 4.20102 5.73223 3.73218C6.20107 3.26334 6.83696 2.99995 7.5 2.99995C8.46469 2.98314 9.41003 3.45121 10.2127 4.34311C11.0154 5.23501 11.6383 6.50935 12 7.99995C12.3617 6.50935 12.9846 5.23501 13.7873 4.34311C14.59 3.45121 15.5353 2.98314 16.5 2.99995C17.163 2.99995 17.7989 3.26334 18.2678 3.73218C18.7366 4.20102 19 4.83691 19 5.49995C19 6.16299 18.7366 6.79887 18.2678 7.26772C17.7989 7.73656 17.163 7.99995 16.5 7.99995"
        stroke={fillColor}
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
  );
}
