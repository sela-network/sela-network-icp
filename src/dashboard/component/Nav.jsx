import React from 'react';
import { Layout } from 'antd';
const { Footer, Sider } = Layout;

import SelaLogo from './SelaLogo';
import AppMenu from './AppMenu';
import Spacing from './Spacing';

const Nav = ({ menuItems, onMenuClick, selectedMenu }) => {
  return (
    <Sider width={350} style={{ position: 'fixed', height: '100%', left: 0 }}>
      <SelaLogo />

      <Spacing margin={64} />

      {menuItems.map((item, index) => (
        <div key={index} onClick={() => onMenuClick(item)}>
          <AppMenu
            leftIcon={item.leftIcon}
            text={item.text}
            isActive={selectedMenu.text == item.text}
          />
        </div>
      ))}
    </Sider>
  );
};

export default Nav;
